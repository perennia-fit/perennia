# Plan-Guided Logging

*   **Author:** Leonardo Pinheiro
*   **Status:** In Review
*   **Date:** 2026-11-02

--------------------------------------------------------------------------------

## Overview

A Workout started from a Workout Template arrives with its Sets already in
place: Materialize unrolls each Prescription into incomplete Sets holding the
planned values. Today the Training Screen offers two unrelated ways to log
against them, and they share no state:

*   **The set rows.** Every row has a pencil (edit that one Set), a delete
    button and a drag handle; an incomplete row also has a leading checkbox
    that marks the Set complete with whatever values it holds.
*   **The entry form.** The Track form below the rows is filled from the last
    Set of the previous Workout. Its **Save set** button always creates a new,
    completed Set at the end, leaving the planned rows untouched.

This spec makes the plan drive the Track form. The first incomplete Set of the
exercise is the **Current Set**; the form shows its values; one **Log set**
action fills that Set, marks it complete, starts its rest and, in a superset,
moves to the next exercise of the round. A weight changed while logging
carries to the later planned Sets that had the same planned weight, so a
missing weight is typed once. A changed rest sticks, and is remembered for the
exercise through the Sets themselves. The Workout screen, Navigation Panel and
Today show what is done and what is current; starting from Up next opens a
preview first; and an exercise can be replaced inside a Workout.

The vocabulary is [CONTEXT.md](../../CONTEXT.md); how the app is layered is
[ARCHITECTURE.md](../../ARCHITECTURE.md); the invariants and process are
[AGENTS.md](../../AGENTS.md); styling is [DESIGN.md](../../DESIGN.md).

## The Problem

Reported from a real Workout logged on a Routine, then reproduced on the
Android emulator against `main` on 2026-11-02 with a Template holding: a
superset (an Exercise Group named "Superset", 3 rounds) of Incline Dumbbell
Press, "3 × (0 kg × 10, rest 90 s)", and Pull-Up, "3 × (copy previous, rest
60 s)"; then Triceps Pushdown, "2 × (20 kg × 12, rest 0 s)"; then Dumbbell
Curl with no Prescription.

1.  **Two sources of truth on one screen.** Incline Press's planned rows said
    0 kg × 10; the form below them said 26 kg × 10 (from last session).
    Pull-Up's rows said 9 reps and its form 7 reps: copy-previous takes the
    latest completed Set by `performedAt`, while the form takes the
    highest-position Set of the previous Workout.
2.  **The checkbox logs the wrong numbers.** Ticking a planned row recorded
    0 kg × 10 as a Performed Set. A completed row loses its checkbox and cannot
    be returned to planned.
3.  **Save set never fills the plan.** It appended a fourth Set after the three
    planned ones, so the list read done, planned, planned, done; the only
    difference between done and planned rows is the planned rows' checkbox.
4.  **An edit stays on one Set.** The pencil changes one Set and nothing else;
    a weight missing from the plan has to be typed on every Set, and the value
    typed is never carried into the form.
5.  **The rest timer forgets.** A Set created by Save set has no planned rest,
    so its rest is the hard-coded 120 s. The timer panel's seconds field, with
    its Start/Update button, starts a one-off timer that the next Save replaces
    with 120 s again. Editing a Set never starts a timer.
6.  **Supersets don't walk.** Only Save set moves to the next member of an
    Exercise Group; the checkbox and the pencil don't. A planned Set can be
    deleted, but none can be added, from inside the Workout.
7.  **No progress view.** "3 sets" counts planned and done alike on the Workout
    screen, the Navigation Panel and Today. Nothing marks the exercise in
    progress, and the Workout screen is titled "Workout" rather than the name
    of the Template it came from.
8.  **Starting is not deliberate.** One tap on an Up next card materializes the
    Workout, so looking at what is planned starts it.
9.  **No replace.** Swapping an exercise (the machine is taken) means removing
    one, adding another and re-entering the plan by hand.

Three bugs found on the way are fixed by
[perennia-fit/perennia#88](https://github.com/perennia-fit/perennia/pull/88)
and are not part of this spec. This spec assumes it has merged, with this API:

*   `RestTimerRepository.startForSet(LoggedSetRecord set, {Duration
    defaultDuration, double alertVolume, String actor, String? batchId,
    DateTime? now})` returns `Future<String?>`: `null`, starting nothing and
    leaving a running timer alone, when the Set's `plannedRestAfter` is zero;
    otherwise it starts `plannedRestAfter ?? defaultDuration`.
*   `LoggedSetRepository.findLatestPriorForExercise` reads only Performed Sets.
*   The Training Screen's number fields select their value on tap.

## Goals

*   One way to log against a plan: the Track form shows the Current Set and
    **Log set** fills it.
*   Logging a repeat planned Set stays at most two taps: open the exercise,
    **Log set**.
*   A weight changed while logging carries to the later planned Sets that had
    the same planned weight, so it is typed once.
*   A changed rest sticks for the rest of the exercise in this Workout and is
    remembered for the exercise next time, with no new stored field.
*   Supersets advance through the round after every logged Set.
*   Planned Sets can be added, a round added to a superset, and planned Sets
    removed with an undo, inside the Workout.
*   Done, planned and current are visible on the Training Screen, the Workout
    screen, the Navigation Panel and Today.
*   Tapping an Up next card previews; a separate Start control starts.
*   An exercise can be replaced in a Workout, keeping its place, its superset
    and its remaining plan.

## Non-Goals

*   **A schema change.** Nothing here adds a column or a table; the remembered
    rest is derived from Sets.
*   **Changing the Template while logging.** Edits stay in the Workout. The
    Finish-time prompt and the Workout menu's **Update template** remain the
    only ways a Workout writes back to its Template.
*   **Template Group rounds at Materialize.** Materialize ignores a Template
    Group's `rounds`; this spec does not change that (Open Question 1). Rounds
    in a Workout are derived from Set counts.
*   **Unifying the two "last session" lookups** (copy-previous at Materialize
    against the form's prefill). With this spec the form shows the plan
    whenever there is one, so the disagreement no longer shows on the same
    screen; unifying them changes Materialize and its golden vectors and is
    separate work.
*   **The History and Graph tabs** that AGENTS.md describes for the Training
    Screen. They are not built today and stay out of scope.
*   **Discarding a started Workout**, a default-rest setting, rest timers for
    agents (they are device-only rows), the unused `markSetsCompleteByDefault`
    setting, and a timer on the Workout screen.
*   **A new agent operation.** See [Agent surface](#agent-surface).

## Open Questions

None blocks building. Each was decided as below and can be overturned in
review:

1.  **Rounds at Materialize.** Whether a Template Group's `rounds` should
    multiply its members' Prescriptions is a separate decision. The round shown
    in a Workout is derived from Set counts, which is right under either
    answer, and the preview shows no round count until Materialize uses it.
2.  **Unlogged Planned Sets at Finish.** The divergence comparison counts every
    active Set, planned or performed. That stays: a plan not finished is not a
    reason to rewrite the Template.
3.  **Which dimensions carry forward.** Only load (see
    [Carry-forward](#carry-forward)). Reps, duration and distance are outcomes
    of a Set, and carrying a missed rep would quietly lower the rest of the
    plan.

## Critical User Journeys (CUJs)

The setting **Auto-select next set** (`autoSelectNextSet`, an existing account
setting under Settings › Logging, default on) is on unless a CUJ says
otherwise.

### CUJ 1: Log a planned Set

*   **Given** a Workout started from a Template with "3 × (60 kg × 10, rest
    90 s)" for Bench Press,
*   **When** the user opens Bench Press,
*   **Then** row 1 is the Current Set (highlighted, arrow icon), rows 2 and 3
    are planned (secondary text), the form shows 60 kg, 10 reps, **Rest after**
    1:30, and the button reads **Log set 1 of 3**.
*   **When** they tap **Log set 1 of 3**,
*   **Then** row 1 shows a check, row 2 becomes current, the confirmation
    "Set 1 logged" shows with **Undo**, a 90 s rest runs in the rest strip
    above the button, and the button reads **Log set 2 of 3**.

### CUJ 2: A weight missing from the plan

*   **Given** Incline Press planned as three Sets of 0 kg × 10,
*   **When** the user sets the load to 26 and logs Set 1,
*   **Then** Set 1 is performed at 26 kg × 10, Sets 2 and 3 now show
    26 kg × 10, and the confirmation reads "Set 1 logged · 2 later sets
    updated" with **Undo**.
*   **And** at Finish the existing prompt offers to update the Template, which
    would write 26 kg into the Prescription.

### CUJ 3: A missed rep does not lower the plan

*   **Given** Squat planned as 3 × 100 kg × 5,
*   **When** the user logs Set 1 at 100 kg × 4,
*   **Then** Sets 2 and 3 still show 100 kg × 5.

### CUJ 4: A pyramid keeps its shape

*   **Given** planned Sets 0 kg × 10, 0 kg × 8, 0 kg × 6,
*   **When** the user logs Set 1 at 40 kg × 10,
*   **Then** Sets 2 and 3 show 40 kg × 8 and 40 kg × 6.

### CUJ 5: Change the rest

*   **Given** Bench Press's Current Set has a planned rest of 90 s,
*   **When** the user steps **Rest after** to 2:00 and logs the Set,
*   **Then** a 120 s rest starts, the remaining planned Sets of Bench Press that
    were planned at 90 s now carry 120 s, and the next time Bench Press is
    logged without a planned rest (an extra Set, a Workout not from a
    Template), **Rest after** starts at 2:00, until a later logged Set of
    Bench Press carries a different planned rest.

### CUJ 6: An unchanged rest changes nothing

*   **Given** a Template whose Prescriptions have no rest,
*   **When** the user logs every Set without touching **Rest after**,
*   **Then** each rest runs at the remembered rest (or 120 s), no Set stores a
    planned rest, and Finish raises no Template-update prompt for rest.

### CUJ 7: Walk a superset

*   **Given** a superset named "Superset" of Incline Press and Pull-Up, three
    planned Sets each,
*   **When** the user logs Incline Press Set 1,
*   **Then** the screen moves to Pull-Up, whose context line reads
    "Superset · Round 1 of 3 · Next: Incline Press".
*   **When** they log Pull-Up Set 1,
*   **Then** the screen returns to Incline Press and the line reads
    "Superset · Round 2 of 3 · Next: Pull-Up".
*   **When** all six are logged,
*   **Then** the screen stays on Pull-Up, the line reads "Superset · All rounds
    done", and a **Next: Triceps Pushdown** button appears.

### CUJ 8: One more Set

*   **Given** every planned Set of Triceps Pushdown is done,
*   **When** the user taps **Log set**,
*   **Then** a third Set is performed with the form's values, and the screen
    stays on Triceps Pushdown.
*   **Or when** they tap **Add set**, a third planned Set appears with the last
    Set's values and planned rest, and becomes the Current Set.

### CUJ 9: Fix a logged Set

*   **Given** Set 1 is performed and Set 2 is current,
*   **When** the user taps row 1,
*   **Then** row 1 is selected (the only highlighted row), the form shows its
    values, and the buttons are **Update** and **Delete**, with **Not done**
    above them.
*   **When** they tap **Not done**,
*   **Then** Set 1 is planned again and is the Current Set.

### CUJ 10: Remove a planned Set by mistake

*   **When** the user swipes planned row 3 away,
*   **Then** it is removed and "Planned set removed" shows with **Undo**, which
    restores it.

### CUJ 11: See where I am

*   **Given** a Workout from "Upper B" where the superset of Incline Press
    (2 of 3 done) and Pull-Up (2 of 3 done) is in progress, Triceps Pushdown
    has 0 of 2 done, and Dumbbell Curl has 2 Performed Sets and no plan,
*   **When** the user opens the Workout,
*   **Then** it is titled "Upper B"; the cards read "2/3 sets", "2/3 sets",
    "0/2 sets" and "Done" (with a check); Incline Press, the superset's first
    card, also shows "Round 3 of 3" and **Now**.
*   **And** Today's tile for this Workout reads "Open - In progress - 4 exercises -
    6 of 10 sets".

### CUJ 12: Look before starting

*   **Given** Up next shows "Upper B",
*   **When** the user taps the card,
*   **Then** a preview sheet lists the exercises with their Prescriptions and
    supersets, with a **Start** button; nothing is started.
*   **When** they instead tap the card's ▶ button,
*   **Then** the Workout starts and opens, as a card tap does today.

### CUJ 13: Replace an exercise

*   **Given** the superset [Pull-Up, Incline Press], Incline Press with one
    performed and two planned Sets,
*   **When** the user chooses **Replace exercise** on Incline Press and picks
    Incline Machine Press,
*   **Then** the order reads Pull-Up, Incline Machine Press, Incline Press; the
    superset is [Pull-Up, Incline Machine Press]; Incline Machine Press holds
    two planned Sets with the old planned rests and its own last performed
    values; Incline Press keeps its performed Set outside the superset; and the
    screen shows Incline Machine Press with "Replaced · Undo".

### CUJ 14: The app is killed mid-exercise

*   **Given** Set 2 of 3 was just logged and its rest is running,
*   **When** the app is killed and reopened on the exercise,
*   **Then** Set 3 is the Current Set, the round line is correct, and the rest
    resumes from its stored deadline.

### CUJ 15: An agent logs a planned Set

*   **Given** a materialized Workout open on the phone,
*   **When** an Agent completes Set 1 through `batchWriteAgentWorkout` with
    `isCompleted: true` and new values,
*   **Then** on the phone (after sync) Set 1 shows as performed and Set 2
    becomes the Current Set. The Agent's skill guide tells it to set
    `performedAt` and to apply the load to later planned Sets itself, as the
    app's carry-forward does.

## Technical Plan (Architecture)

### Overview of the parts

| Part | Where | Change |
| :--- | :---- | :----- |
| Plan logging rules | `apps/mobile/lib/domain/training/plan_logging.dart` (new) | Pure functions: Current Set, carry-forward, next group member, group round, rests, Current Exercise, next exercise |
| Logging writes | `LoggedSetRepository` | `logSet`, `findRememberedRest`; existing writes reused |
| Timer | `RestTimerRepository.adjust`; the rest strip | Adjust a running timer; the panel becomes a strip above Log set |
| Training Screen | `training_screen.dart` | Row states, the form driven by the Current Set, Log set, Update mode, Rest after, context line, Add set, Add round, Next |
| Progress | `home_repository.dart`, `workout_screen.dart`, `home_screen.dart`, the Navigation Panel | Template name, done/planned counts, Now, round line |
| Start | `up_next_strip.dart`, `template_picker_sheet.dart` | Tap previews, ▶ starts |
| Replace | `WorkoutExerciseRepository.replace`, entry points | New |

### Vocabulary

New terms, added to [CONTEXT.md](../../CONTEXT.md) after **Performed Set** by
the first implementation pull request:

*   **Planned Set.** A Set that is not deleted, belongs to a Workout that is
    not deleted, and is not complete: a target placed by a Workout Template, a
    quick log, an Agent, Add set, or Not done. It holds the values the plan
    expects and never counts as training. Logging it makes it a Performed Set.
*   **Current Set.** For one Workout Exercise, the Planned Set the Track form
    fills on Log set: the first Planned Set in order, unless the user picked
    another. Derived, never stored.
*   **Current Exercise.** The Workout Exercise, or the Exercise Group, the user
    is working through, marked **Now**. Derived from the Workout's Sets, never
    stored.
*   **Remembered Rest.** For one Exercise, the planned rest of its most
    recently performed Set that has one. Used as the rest when a Set has no
    planned rest. Derived, never stored.

The **Performed Set** entry's sentence "Saving a Set on the Track tab marks it
complete" becomes "Logging a Set on the Training Screen marks it complete".

UI copy uses "set", "planned", "done", "Now" and "Rest after"; "Current Set",
"Current Exercise" and "Remembered Rest" are code and spec words.

### Ordering

Within one Workout, the Sets of a Workout Exercise are the active Sets with
that Workout's id and that Exercise's id (a Set has no Workout Exercise id, and
an Exercise appears at most once per Workout). Everything in this spec orders
them by `position`, then `id`. `LoggedSetRepository.watchActiveForWorkout`
gains `id` as a second ordering term so the screen list uses the same order.
"Later" means later in this order, never a raw `position` comparison
(positions can tie: Materialize numbers each exercise from 0, and Agents
supply their own).

The members of an Exercise Group are ordered by member `position`, which is
selection order for a group made in the Navigation Panel, not necessarily
Workout order. Workout Exercises are ordered by their `position`.

### Plan logging rules

`plan_logging.dart` holds the rules as pure functions over records, tested
without a database.

```dart
/// The Planned Set the form fills, or null when no Set is planned.
LoggedSetRecord? currentSetFor(
  List<LoggedSetRecord> exerciseSets, { // in Ordering's order
  String? pickedSetId,
});

class CarryTarget {
  final String setId;
  final SetDimensionValue? load;   // non-null: write this load
  final Duration? rest;            // meaningful only when restChanged
  final bool restChanged;
}

/// The later Planned Sets that take a logged Set's new load or rest.
List<CarryTarget> carryForwardFor({
  required List<LoggedSetRecord> exerciseSets,
  required LoggedSetRecord logged,        // as stored before the write
  required LoggedSet newValues,
  required bool restChanged,
  required Duration? newRest,
});

/// The member Log set moves to, or null to stay.
String? nextGroupMemberAfterLog({
  required List<String> memberIdsInOrder,  // empty when ungrouped
  required String loggedWorkoutExerciseId,
  required Set<String> membersWithPlannedSetBefore, // before the write
  required bool loggedAPlannedSet,  // the Log set filled a Current Set
  required bool autoSelectNextSet,
});

sealed class GroupRound {}
class GroupRoundInProgress extends GroupRound { final int round; final int of; }
class GroupRoundAllDone extends GroupRound {}

/// Null when no member has a Set.
GroupRound? groupRoundFor(List<({int performed, int planned})> members);

/// The rest the form shows for [shownSet] (the Current Set, or the
/// performed Set selected for Update), or for a new Set when it is null.
Duration restShownFor({
  required LoggedSetRecord? shownSet,
  required LoggedSetRecord? lastSetOfExercise, // in this Workout
  required Duration? rememberedRest,
});

class ProgressExercise {
  final String workoutExerciseId;
  final String? groupId;
  final int performed;
  final int planned;
  final DateTime? latestPerformedAt; // over its Performed Sets
}

sealed class CurrentExercise {}
class CurrentWorkoutExercise extends CurrentExercise { final String workoutExerciseId; }
class CurrentGroup extends CurrentExercise { final String groupId; }

/// [exercises] in Workout order.
CurrentExercise? currentExerciseFor(List<ProgressExercise> exercises);

/// The Workout Exercise after [fromWorkoutExerciseId] (after its group when
/// grouped), in Workout order and wrapping, that has a Planned Set.
String? nextExerciseWithPlan({
  required List<ProgressExercise> exercises,
  required String fromWorkoutExerciseId,
});
```

**Current Set.** If `pickedSetId` names a planned Set in the list, that Set;
otherwise the first planned Set; otherwise null.

#### Carry-forward

Let `L` be the Set being logged as stored before the write, `V` the form's
values and `R` the form's rest.

*   **Load.** Only when the exercise records load and `V`'s load differs from
    `L`'s stored load (same `entered` text and same unit counts as equal;
    `SetDimensionValue` equality). Then every later Planned Set `P` whose load
    equals `L`'s stored load takes `V`'s load. Its other dimensions are left as
    they are.
*   **Rest.** Only when the user changed **Rest after** for this Set (see
    [Rest](#rest)). Then every later Planned Set `P` whose `plannedRestAfter`
    equals `L`'s stored `plannedRestAfter` (two nulls are equal) takes `R`.
*   A `P` that would receive values it already holds is not a target. Comment,
    side and RPE never carry. Sets before `L` are never targets.

Load is the value chosen before a Set; reps, duration and distance are what
happened in it. Carrying only load fixes the missing weight (CUJ 2) without
lowering a plan after a missed rep (CUJ 3), and works for a pyramid, whose reps
differ but whose planned load is the same (CUJ 4).

#### Next group member

When `autoSelectNextSet` is false, or `memberIdsInOrder` has fewer than two
ids, the result is null. Otherwise:

*   **A planned superset** (`loggedAPlannedSet` is true): walk the members in
    order starting after the logged one, wrapping, and return the first one
    other than the logged one that is in `membersWithPlannedSetBefore` and
    still has a Planned Set after the write (for the logged member itself,
    that means it had more than one). If none, null: the screen stays (CUJ 7).
    This interleaves A1, B1, A2, B2; a member with more Sets keeps its turn
    once the others run out.
*   **A freestyle superset, or a Set logged after the plan** (`loggedAPlannedSet`
    is false): the next member in order, wrapping, as Save set does today.

An ungrouped exercise never moves on its own, so the user can add a Set after
the plan (CUJ 8). `ExerciseGroupRepository.findNextWorkoutExerciseIdAfter` is
deleted; its only caller is the Save set path this spec replaces, and the
freestyle branch reproduces it.

#### Group round

Leave out members with no Sets (`performed + planned == 0`). If none remain,
the result is null (no round line). If none of the rest has a Planned Set,
`GroupRoundAllDone`. Otherwise `of = max(performed + planned)` and
`round = of − max(planned) + 1`: the round is set by the member with the most
left to do. This reads right when members have unequal counts, and when a
member was replaced mid-superset (its replacement starts with no Performed
Set but the same number of Sets left as the others).

#### Rest

*   **Rest shown** for a Set (the Current Set, or a performed Set selected for
    Update): its `plannedRestAfter` when not null; otherwise `rememberedRest`;
    otherwise 120 s (`RestTimerRepository.defaultDuration`). For a new Set (no
    Current Set): `lastSetOfExercise`'s `plannedRestAfter` when not null;
    otherwise `rememberedRest`; otherwise 120 s.
*   **Changed** means the **Rest after** value differs from the rest shown
    when the form last loaded (stepping up and back down is not a change).
    Only a changed rest is written as `plannedRestAfter` and carried forward.
    An unchanged rest leaves the stored `plannedRestAfter` as it was (null
    stays null), so a Template with no rest never diverges because of Log set
    (CUJ 6).
*   **The rest that runs** after Log set is the form's rest (changed or not).
    When it is zero, no timer starts.
*   **Remembered Rest** is read by
    `LoggedSetRepository.findRememberedRest(String exerciseId)`: the
    `plannedRestAfter` of the exercise's Performed Set, in a Workout that is
    not deleted, with `plannedRestAfter` greater than zero, latest by
    `performedAt` (nulls last), then the Workout's `startedAt`, then
    `position`, then `id`, all descending. Zero is skipped because a planned
    rest of zero is a statement about one plan (go straight to the next
    superset member), not a preference for the exercise; so Off is never
    remembered. Because a changed rest is written onto the Set, it becomes the
    Remembered Rest (CUJ 5); a later Template rest logged for the same
    exercise replaces it. Sets sync, so this works on every device, for
    Platform and User Library exercises alike, and an Agent reads it through
    the Sets it already reads.

#### Current Exercise and next exercise

`currentExerciseFor`:

1.  The first Workout Exercise in Workout order that is **in progress**: it,
    or (when grouped) its group, has both a Performed Set and a Planned Set
    across its members. The result is it, or its group.
2.  Otherwise, `nextExerciseWithPlan` from the exercise with the latest
    `latestPerformedAt` (or its group).
3.  Otherwise, with no Performed Set at all, the first exercise in order with
    `planned > 0` (or its group).
4.  Otherwise null.

Rule 1 keeps **Now** on a superset whose member was just replaced (CUJ 13):
the old exercise, moved after the group, holds the latest Performed Set but
the group is still in progress.

`nextExerciseWithPlan` walks the Workout Exercises in Workout order, starting
after `fromWorkoutExerciseId`, skipping every member of its group when it is
grouped, wrapping, and returns the first with `planned > 0`; it never returns
the start exercise or a member of its group. The **Next** button uses it from
the open exercise.

### Logging writes

`LoggedSetRepository.logSet(LogSetRequest request, {required String batchId})`
runs one Drift transaction. Every touched row gets exactly one update and one
Activity Log entry under `batchId`, so `undoBatch(batchId)` reverses the whole
action without conflicts.

```dart
class LogSetRequest {
  final String workoutId;
  final String exerciseId;
  final String? currentSetId;   // null: create a new Performed Set
  final LoggedSet values;
  final String? comment;
  final SetSide? side;
  final double? rpe;
  final bool restChanged;
  final Duration? rest;         // written only when restChanged
}

class LogSetResult {
  final String setId;
  final int carriedCount;
  final bool alreadyLogged;     // the Current Set was complete or gone
}
```

1.  **With `currentSetId`.** Load it. If it is deleted or already complete,
    return `alreadyLogged: true` and write nothing (a second tap, or another
    device logged it). Otherwise validate `values` as Save set does today
    (`_validateValuesForExercise`, which throws on a hard reject), compute `carryForwardFor` from the stored
    rows, and write the Set: values, comment, side, RPE, `plannedRestAfter`
    (only when `restChanged`), `isCompleted = true`, `performedAt = now`.
    Write each carry target in one update.
2.  **Without it.** Create a Set at `nextPositionForWorkout` with values,
    annotations, `plannedRestAfter = rest` when `restChanged` (else null),
    `isCompleted = true`, `performedAt = now`.

`performedAt = now` on completion is new: `setCompleted` leaves `performedAt`
at the time the Set was created, so a Set planned at 9:00 and done at 10:00
read 9:00. The app's own analytics key on the Workout's `startedAt` and are
unaffected; agent analytics that use `performed_at` (for `achievedAt` and
ordering) become accurate for Sets logged this way.

Other writes reuse what exists, each under the batch id the screen passes:

*   **Update** a Performed Set: a new `Future<void>
    updatePerformed(String id, {required LoggedSet values, String? comment,
    SetSide? side, double? rpe, required bool restChanged, Duration? rest,
    required String batchId})` that validates like `updateValues` and writes
    values, annotations and (only when `restChanged`) `plannedRestAfter` in one
    row update with one Activity Log entry. No carry-forward, no timer.
*   **Not done:** `setCompleted(id, isCompleted: false)`.
*   **Add set / Add round:** `create(LoggedSetDraft(isCompleted: false, ...))`
    at `nextPositionForWorkout`, copying the exercise's last Set's values and
    `plannedRestAfter`. For an exercise with no Sets: Add set uses the form's
    values and, when changed, its rest; Add round uses
    `findLatestPriorForExercise` for that member before this Workout, or else
    `zeroLoggedSetFor(its dimensions, its defaultLoadUnit)`, with no planned
    rest. Add round does this for every member, under one batch id. The
    screen stays on the open exercise; its Current Set is recomputed.
*   **Remove a planned Set:** `softDelete`, under its own batch id, shown with
    Undo.
*   **Delete** a Performed Set in Update mode: `softDelete`, shown with Undo.

### Rest timer

*   **The rest strip.** The rest timer panel at the top of the Training Screen
    is replaced by a strip pinned directly above the Log set button, outside
    the scrolling area, in thumb reach:
    *   running: "Rest 1:12" (tabular figures), then **−15 s**, **+15 s** and
        **Stop** icon buttons;
    *   idle: **Start rest** (starts the form's rest; disabled at Off).
    *   Tapping the remaining time opens a small sheet with the existing volume
        slider.
*   **One owner.** The strip keeps today's panel behaviour: it stays mounted
    while the Training Screen switches exercises, owns the ticker, the 3-2-1
    prepare cue and the end alert, and schedules the background notification.
    No other screen shows a timer, so alerts have one owner.
*   **`RestTimerRepository.adjust(String id, Duration delta, {DateTime?
    now})`** changes a running timer's `deadlineAt` and `durationSeconds` by
    `delta`, keeping `durationSeconds ≥ 1`. A new deadline at or before `now`
    becomes `now`, so the strip fires the end alert on its next tick, as for a
    timer that ran out. When the new remaining time is more than 3 s,
    `prepareAlertFiredAt` is cleared. It appends to the Activity Log like the
    other timer writes. After an adjust the strip cancels the background
    schedule and schedules it again; Stop cancels it (as today).
*   **Log set** starts the rest for the logged Set, unless the rest that runs
    is zero or the Workout has ended, with `startForSet(set, defaultDuration:
    <the rest that runs>, alertVolume: <the strip's current volume>)` under
    its **own** batch id, never the Log set's: the timer row is written again
    later (prepare cue, end alert, adjust, Stop), which would make the Log
    set's batch impossible to undo. The strip's volume is its `_alertVolume`
    state, as the panel's is today (1.0 until changed).

### Training Screen

Top to bottom, inside the existing `TrainingScreen` (and `ExercisePage`):

1.  **App bar.** Back; the exercise name; a menu button with **Replace
    exercise** (pull request 4) and **Exercise overview** (the
    `ExerciseOverviewScreen` the Navigation Panel opens today); the Navigation
    Panel button.
2.  **Context line**, only when the Workout Exercise is in an Exercise Group
    with a round: "*group name* · Round *r* of *R* · Next: *member*" ("· Next:"
    left out when Log set would not move), or "*group name* · All rounds done".
    It ends with an **Add round** text button (48 dp tall).
3.  **Set rows**, in [Ordering](#ordering):
    *   *Performed*: index, values, a check icon (`Icons.check`, secondary text
        colour), the existing comment subtitle and record trophy. Semantics:
        "Set *n*, done, *values*".
    *   *Current*: index, values, a leading arrow icon (`Icons.arrow_right`),
        highlighted in translucent primary (DESIGN.md's selected-row
        treatment) unless a performed row is selected. Semantics: "Set *n*,
        next, *values*".
    *   *Planned*: index and values in the secondary text colour. Semantics:
        "Set *n*, planned, *values*".
    *   No checkbox, no pencil, no delete button. The drag handle stays as
        today. A planned or current row is removed by swiping it away
        (`Dismissible`, end to start), which shows "Planned set removed" with
        **Undo**.
4.  **Add set** text button under the rows.
5.  **Form.** The existing dimension steppers; then **Rest after**: [−] and [+]
    in 15 s steps from the current value, clamped to 0..60:00, showing "m:ss",
    or "Off" at zero; then comment, side and RPE as today.
6.  **Rest strip** (above), then the **buttons**, pinned outside the scroll:
    *   with a Current Set and nothing selected: **Log set *n* of *m***
        (`button-save`), *n* the Current Set's 1-based place among the
        exercise's Sets, *m* their count;
    *   with no Current Set and nothing selected: **Log set**;
    *   with a performed row selected: **Not done** (text button) above
        **Update** (`button-save`) and **Delete** (`button-destructive`) side
        by side; Log set is hidden;
    *   below, with nothing selected, when this Workout Exercise (and every
        member of its group, when grouped) has no Planned Set and
        `nextExerciseWithPlan` returns one: **Next: *name*** (outlined),
        opening it.

DESIGN.md's Save and Clear buttons are replaced by Log set; there is no Clear.

#### Screen state

**Data the screen holds.** `_TrainingExerciseState` gains the `workout`
(`WorkoutSessionRecord`, for `endedAt`) and `rememberedRest` (`Duration?`,
from `findRememberedRest`, read with the existing prefill). The screen
subscribes, for the whole Workout, to the streams the Navigation Panel already
uses: `workoutExercises.watchActiveForWorkout(workoutId)`,
`sets.watchActiveForWorkout(workoutId)` (today filtered to one exercise; the
screen keeps the unfiltered list and filters it for the rows) and
`exerciseGroups.watchActiveForWorkout(workoutId)`. The context line, the
Next button, `nextGroupMemberAfterLog` and the rounds read them. The
Navigation Panel keeps its own subscriptions.

**Screen state** lives in the widget's state, as today:

*   `pickedSetId` (`String?`) and `selectedSetId` (`String?`, a performed row
    in Update mode);
*   `formUnits` (`Map<DimensionId, TrainingUnit>`): the unit of each dimension
    field, set on every form load; `_valuesFromControllers` writes these units
    and the dimension labels and steppers show them;
*   `loadedRest` (`Duration`): the rest shown at the last form load; the rest
    is **changed** when **Rest after** differs from it;
*   `formDirty` (`bool`): set by any change to any form control (typing, a
    stepper, Rest after, side, RPE, comment);
*   `logInFlight` (`bool`).

| Event | Result |
| :---- | :----- |
| Open an exercise, or switch exercise | `pickedSetId`, `selectedSetId` null; form loads |
| Tap a planned row | `selectedSetId` null; `pickedSetId` = it; form loads |
| Tap the current row | `selectedSetId` null; form loads the Current Set |
| Tap a performed row | `selectedSetId` = it; form loads that Set |
| Tap the selected row again | `selectedSetId` null; form loads the Current Set |
| Log set | `pickedSetId` null; form loads the next Current Set |
| Update | `selectedSetId` null; form loads the Current Set |
| Delete (Update mode) | `selectedSetId` null; "Set deleted" with Undo; form loads the Current Set |
| Not done | `selectedSetId` null; `pickedSetId` = that Set; form loads it |
| The selected Set stops being performed or is deleted (sync, Undo, an Agent) | `selectedSetId` null; form loads the Current Set |

**Form loads** a Set (the Current Set, or the selected performed Set): the
dimension fields take its values, and `formUnits` its units (not the unit
setting); comment, side and RPE take its annotations (empty when it has none);
**Rest after** and `loadedRest` take the rest shown; `formDirty` becomes false.

**With no Current Set and nothing selected**, the form keeps the values last
logged on this exercise in this visit, or else takes the prefill from the
previous Workout (as today), with `formUnits` from the unit setting; comment
and RPE clear and side alternates after each Log set, as Save set does today;
Rest after shows the rest for a new Set.

**Reloads.** While `selectedSetId` is set, the form never reloads on its own.
Otherwise it reloads when the Current Set's id changes, or when the Current
Set's stored values or rest change while `formDirty` is false (a
carry-forward, a sync or an Agent write).

#### Log set, step by step

1.  If `logInFlight`, ignore the tap.
2.  Parse the form as Save set does today: if a field doesn't parse,
    return without writing or showing anything (as today). Soft warnings are
    not shown, as today.
3.  Set `logInFlight`. Create a batch id. Compute, from the state before the
    write, the inputs of `nextGroupMemberAfterLog`.
4.  Show the confirmation within one frame: "Set *n* logged", without an
    action yet. *n* is the logged Set's 1-based place among the exercise's
    Sets (for a new Set, its count after the write).
5.  Await `logSet`, inside `try`/`finally` that clears `logInFlight`.
    *   It throws (a hard reject, a missing Exercise): hide the confirmation
        and show "Set not logged" with the error's message.
    *   It returns `alreadyLogged`: hide the confirmation; nothing else.
6.  Start the rest (see [Rest timer](#rest-timer)), keeping its timer id.
7.  Replace the confirmation with one carrying **Undo**: "Set *n* logged",
    or "Set *n* logged · *k* later sets updated" when `carriedCount > 0`.
8.  Switch to the next member, if any.

**Undo** of Log set calls `undoBatch(logBatchId)`, which restores the Set to
planned (or removes a new one) and reverts the carry-forward; then, if the
timer from step 6 is still the Workout's current timer, cancels it and its
background schedule. Undo removes the logged values too; the user logs again.
Undo of Remove, Delete, Add round and Replace calls `undoBatch` on that
action's batch id. When `undoBatch` reports conflicts (another write touched
the same rows since), nothing is reverted and "Couldn't undo: changed since"
shows.

### Progress on the Workout screen, Today and the Navigation Panel

*   **Data.** `HomeSetSummary` gains `performedAt` (`DateTime?`).
    `HomeWorkoutExerciseSummary` gains `performedCount`, and
    `HomeWorkoutSummary` gains `performedSetCount` and `templateName`
    (`String?`, part of equality). `templateName` comes from a new
    `TemplateMaterializeRepository.watchByWorkoutIds(Set<String>)` (the
    Template Links of those Workouts) combined with
    `workoutTemplates.watchAllSummaries()` (archived Templates included), both
    added to the streams `_watchTrainingDay` and `_watchWorkout` already
    combine, and passed to `_homeSummaryFrom` as a
    `Map<String, String> templateNameByWorkoutId`. A renamed Template renames
    the title of its Workouts, past ones included: the link is a reference,
    never a snapshot.
*   **Title.** `templateName` when present, otherwise "Workout".
*   **Exercise card.** When it has Sets and no Planned Set: a check icon and
    "Done" instead of the count. When it has a Planned Set:
    "*performed*/*total* sets". With no Sets: "No sets", as today. The first
    card of a group with a round also shows "Round *r* of *R*" or "All rounds
    done" beside the existing group bar. The Current Exercise's card (or its
    group's first card) shows **Now** (text, `label` style, primary colour),
    on open Workouts only.
*   **Cards, link icons, reordering, swipe to remove:** unchanged.
*   **Today.** A Workout tile's last segment reads "*performed* of *total*
    sets" when the Workout has a Planned Set, else "*n* sets" (today's
    `'$status - $duration - $exerciseCount - $setCount'` shape is kept). The
    day status line (`_formatTrainingDayStatus` in `home_repository.dart`)
    counts only Workouts with at least one Performed Set, and their Performed
    Sets; a day whose only Workout holds no Performed Set reads "No workout
    started", as an empty day does.
*   **Navigation Panel.** Each exercise shows the same count text as its card
    and the **Now** label; the open exercise stays highlighted as today. It
    reads the Sets it already watches.

### Starting from Up next and the Routines sheet

*   **Up next card.** The body opens `showTemplatePickerPreviewSheet`; a
    trailing ▶ icon button (48 dp, the existing `homeUpNextStartTooltip`
    label, "Start *name*") runs today's start path (`confirmTemplateStart`,
    materialize, open the Workout). The preview's **Start** runs the same path.
    Done cards are unchanged.
*   **Routines sheet.** A row tap opens the preview (the eye icon goes); a
    trailing ▶ starts.
*   **Preview.** `TemplatePickerPreviewSheet` shows, under each exercise name,
    one line per Prescription in the template editor's existing format
    ("3 × (60 kg · 10 reps, Rest after 90 sec)", "3 × (Copy previous values)"),
    by moving `_prescriptionSummary` from `workout_template_editor_screen.dart`
    to a shared `prescription_summary.dart` used by both. Members of a Template
    Group sit under a header with the group's name (no round count; Open
    Question 1).

### Replace an exercise

`WorkoutExerciseRepository.replace(String workoutExerciseId, String
newExerciseId, {required String batchId})` returns the new Workout Exercise's
id, or throws `AlreadyInWorkoutException` when the new Exercise is already
active in the Workout (checked first, because `_create` quietly returns the
existing row). It runs in one transaction and **writes every row at most
once** under `batchId`, so `undoBatch` can reverse it: the existing
`create`, `reorderForWorkout` and `exerciseGroups.update` each write their own
entries (and the reorder rewrites rows it just wrote), so `replace` does not
call them. With `old` the Workout Exercise:

1.  **Plan the final order** of the Workout's active Workout Exercises: the
    new one takes `old`'s index. If `old` keeps a Performed Set, it moves to
    directly after the last member of its group (grouped) or directly after
    the new one (ungrouped); otherwise it leaves the list. Every group's
    members stay adjacent, which the reorder's group reconciliation relies on.
2.  **Insert** the new Workout Exercise at its final position, through a new
    private insert that takes a position, and **write each other Workout
    Exercise whose position changes** once.
3.  If `old` is in an Exercise Group, **write the member row** that pointed at
    `old` so it points at the new Workout Exercise (same group, same member
    position): one write, no group reconciliation.
4.  For each Planned Set of `old`, in order: soft-delete it and create a
    Planned Set for the new Exercise with the same `position` and
    `plannedRestAfter`, and values from `findLatestPriorForExercise` for the
    new Exercise before this Workout (dimensions matching its Exercise Type),
    or else `zeroLoggedSetFor(the new type's dimensions, its defaultLoadUnit)`.
5.  If `old` has no Performed Set, soft-delete `old` (one write; its Sets are
    already handled in step 4 and it has no group membership left).

The Template is not changed; the Finish prompt reports the difference as for
any edit. Replacing back is not offered: the old exercise is still in the
Workout when it keeps a Performed Set, so picking it reports "Already in this
workout".

**Entry points** (pull request 4): the Training Screen's app-bar menu, and a
new ⋮ button (48 dp) on each Workout screen card with **Replace exercise**.
Both call `Future<String?> replaceExercise(BuildContext, WidgetRef, String
workoutExerciseId)` in `replace_exercise.dart`: it opens the existing
`ExerciseCatalogPicker` in a modal sheet with `initialFocusId` set to the
Workout's Focus, calls `replace`, shows "Replaced" with **Undo** or "Already in
this workout", and returns the new id (null when cancelled or refused). The
Training Screen switches to the new id; the Workout screen stays.

### Agent surface

*   **No contract change.** No new operation, schema or field.
*   **Logging.** An Agent already writes complete Sets through
    `batchWriteAgentWorkout`, including `isCompleted`, `plannedRestAfter` and
    `performedAt`. The Current Set, carry-forward and the Remembered Rest are
    derived by the app from the Sets the Agent writes, so the app shows an
    Agent's logging correctly (CUJ 15). Carry-forward is how the app's form
    saves a person typing; an Agent writes each Set's values itself.
*   **Skill guide.** `agent-skills/perennia/SKILL.md` gains a short rule under
    its workout-logging guidance. `batchWriteAgentWorkout` writes whole Set
    rows, and omitted fields default to null, so: when completing a Planned
    Set, read the Workout first and send the Set back with every stored field
    unchanged (`plannedRestAfter` above all, which a null would erase) except
    `values`, `isCompleted: true` and `performedAt` (when it was done); send a
    new `plannedRestAfter` only for a rest the user chose; when the user's load
    differs from the plan, also write it on the later Planned Sets that had the
    same planned load.
*   **Replace.** An Agent replaces an exercise's remaining plan through
    `batchWriteAgentWorkout` by tombstoning the old Sets and writing Sets for
    the new exercise. Workout Exercise Groups are not writable by Agents today,
    so the group step has no Agent counterpart; that gap exists before this
    spec and is unchanged.

### Invariants

*   **A Workout is a session.** Unchanged.
*   **Sets are self-describing.** Log set writes the entered text in the
    Current Set's own units; carry-forward copies a load's entered text and
    unit exactly.
*   **Derived analytics are computed, never stored.** Current Set, Current
    Exercise, Remembered Rest, rounds and counts are derived on every read; no
    column stores them.
*   **User-facing delete is archive for exercises and categories.** Unchanged;
    removing a Planned Set or replacing an exercise soft-deletes Sets and
    Workout Exercises as removing them does today, and Undo restores them.
*   **Restore and import are merge-only.** Untouched; no schema change.
*   **Local writes never block on the network.** Every write is one local
    transaction; the confirmation shows within one frame.
*   **Sync is silent LWW with recoverable losers.** Only Sets, Workout
    Exercises and groups are written, through their existing sync paths.
*   **Validation is one shared module.** Log set validates values through the
    same path as Save set; no rule changes.
*   **No behavioural analytics.** None added.

### Validation and analytics

*   **Validation:** no rule changes. Log set runs the existing set validation
    (hard rejects block, soft warnings confirm).
*   **Analytics:** no computation changes. `performedAt` now records the
    completion time for Sets logged through Log set (see
    [Logging writes](#logging-writes)).
*   **Golden vectors:** none. The plan logging rules are app presentation
    logic with no TypeScript counterpart; they get Dart unit tests.

## Risks and Mitigations

| Risk | Mitigation |
| :--- | :--------- |
| Carry-forward rewrites a load the user meant to keep | Only later Planned Sets with the same planned load; the confirmation names how many changed and offers Undo (which also returns the logged Set to planned, so the user logs it again) |
| Removing the checkbox slows a user who did exactly the plan | Log set with an unchanged form is one tap, and it also starts the rest and advances |
| A double tap logs two Sets | One Log set in flight; an already-logged Current Set is a silent no-op |
| A swipe removes a planned Set by accident | Undo on the confirmation |
| Older Sets completed with a stale `performedAt` | Left as they are; only Log set writes the completion time |

## Alternatives Considered

### Alternative A: Keep the checkbox and the pencil, fix each path

Make the checkbox start the rest and advance, make the pencil carry values.
It keeps two ways to log that can disagree, and the form would still show
values the rows don't.

### Alternative B: Fill zeros from history

Treat a planned "0" as unknown and fill it from the last session. Zero is a
real load (body weight with no added load), and a Set doesn't record whether a
value came from a plan, so the app cannot tell.

### Alternative C: Carry every changed dimension

Copies reps too. A missed rep (100 × 4 instead of 100 × 5) would lower every
later Set to 4, and an unchanged Log set would then record 4. Carrying load
only fixes the reported problem without that.

### Alternative D: A stored rest per Exercise

A nullable `exercises.rest_seconds`, set when the user changes the rest. It
needs a schema version, a sync key, archive handling, agent fields, a
validation rule and golden vectors; it would not sync for Platform exercises,
which never sync. Every Performed Set already carries the rest it was logged
with, so the remembered rest is derived from them instead.

### Alternative E: Remember rest per Workout only

No memory across Workouts, which was the reported problem.

### Alternative F: Rounds stored on Workout Exercise Groups

A `rounds` column could disagree with the Sets; Set counts carry the same
information with no schema change.

### Alternative G: A timer chip in the app bar on every screen

Two mounted screens would each run the ticker and could fire the end alert
twice, and the app bar is out of thumb reach. A strip above Log set keeps one
owner and sits where the thumb is.

### Alternative H: Superset blocks on the Workout screen

One container per group conflicts with DESIGN.md (grouping by the shared bar,
"not by nesting or borders") and with per-card reordering. The round line on
the group's first card gives the progress without it.

### Alternative I: Auto-advance an ungrouped exercise when its plan is done

A user adding a Set after the plan would have to come back. The Next button
is one tap and never surprises.

## Non-Functional Requirements

### Performance

*   Log set shows its confirmation after one `setSaveConfirmationFrameBudget`
    pump (16 ms). The existing performance test and its row in
    `apps/mobile/test/performance/README.md` move from Save set to Log set.
*   `findRememberedRest` runs once when an exercise opens, alongside the
    existing prefill read.

### Accessibility

*   Every new control is at least 48 dp (`AppDimens.touchTarget`).
*   Row state is never colour alone: a check icon on performed rows, an arrow
    on the current row, and every row's semantics label names its state.
*   The swipe to remove has a semantics custom action "Remove planned set".
*   The rows, the context line, the rest strip and Log set keep their text at
    a text scale of 2.0 without overflow; the pinned strip and buttons stay
    visible.
*   The rest strip's remaining time has the semantics label "Rest, *m* minutes
    *s* seconds left".

### Privacy

No new data is stored or leaves the device.

### Rollout and rollback

No flag and no schema change. Each pull request is reverted on its own; Sets
logged under this spec are ordinary Sets.

## Detailed Implementation Plan

Four pull requests, each linking this spec, each cut from `main` after the one
it depends on has merged (no stacked pull requests). Pull request 3 depends on
nothing and can be built any time. Each adds a line under `[Unreleased]` in
`CHANGELOG.md`. The last one to merge sets this spec's Status to **Current**.

### Pull request 1: Log set (Problems 1–6)

#### 1. `apps/mobile/lib/domain/training/plan_logging.dart` (Create)

All the functions and types under [Plan logging rules](#plan-logging-rules).
`currentExerciseFor` is first used by pull request 2; it lands here with
`nextExerciseWithPlan`, which the Next button uses, so the two are tested
together.

#### 2. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

*   `LoggedSetRepository`: `logSet` with `LogSetRequest` and `LogSetResult`;
    `findRememberedRest`; `updatePerformed`; `id` as the second ordering term
    of `watchActiveForWorkout`.
*   `RestTimerRepository.adjust`.
*   Delete `ExerciseGroupRepository.findNextWorkoutExerciseIdAfter` and its
    tests.

#### 3. `apps/mobile/lib/features/training/widgets/training_screen.dart` (Modify)

The layout, state and Log set steps under [Training Screen](#training-screen):
remove the checkbox, pencil and delete button from `_LoggedSetTile` and add the
three row states and the swipe; delete `_EditSetSheet` and `_saveSet` (Log set
replaces them); add Rest after, the context line, Add set, Add round, the
pinned buttons, Update mode, Next, and the app-bar menu with Exercise
overview. New keys: `logSetButtonKey`, `updateSetButtonKey`,
`deleteSelectedSetButtonKey`, `notDoneButtonKey`, `addSetButtonKey`,
`addRoundButtonKey`, `nextExerciseButtonKey`, `restAfterValueKey`,
`restAfterDecrementKey`, `restAfterIncrementKey`, `contextLineKey`,
`restStripKey`, `restStripAdjustKey(int seconds)`, `restStripStopKey`,
`restStripStartKey`, `screenMenuButtonKey`. `saveSetConfirmationKey` is kept
as the Log set confirmation's key (the performance test finds it), and
`restTimerVolumeSliderKey` moves to the strip's volume sheet. Keys of removed
widgets (`saveSetButtonKey`, `editSetButtonKey`, `completeSetCheckboxKey`,
`deleteSetButtonKey`, the edit-sheet keys, `restTimerPanelKey`,
`restTimerDurationFieldKey`, `restTimerStartButtonKey`,
`restTimerCancelButtonKey`) are deleted with their tests.

#### 4. `apps/mobile/lib/features/training/widgets/rest_strip.dart` (Create)

The strip and its volume sheet, carrying the ticker, alerts and background
scheduling moved from `_RestTimerPanel`, plus adjust. Add the file to
`apps/mobile/test/l10n/l10n_externalization_test.dart`.

#### 5. `apps/mobile/lib/l10n/app_en.arb` (Modify)

Every new string of this pull request (Log set labels, the confirmations,
Rest after, Off, the context line, Add set, Add round, Not done, Next, the
rest strip and semantics labels); regenerate the localizations.

#### 6. `CONTEXT.md`, `DESIGN.md`, `apps/mobile/DESIGN.md`, `AGENTS.md` (Modify)

*   CONTEXT.md: the four terms and the Performed Set sentence.
*   DESIGN.md "Set entry" and "Set row": Log set replaces Save/Clear; Update,
    Delete and Not done; the performed, current and planned row states
    replace the checkbox; the rest strip. Mirror the prose in
    `apps/mobile/DESIGN.md` where it has the matching section.
*   AGENTS.md: the Training Screen bullet ("Save/Clear buttons that become
    Update/Delete", "complete checkboxes") becomes Log set, Update/Delete/Not
    done and the row states; the UX rule "(open exercise → Save)" becomes
    "(open exercise → Log set)"; the Navigation Panel bullet's "auto-advance to
    the next group member after a save" becomes "after Log set"; the Routines
    bullet's "one-tap **materialize**" becomes "preview, then **Start**
    (materialize)" (pull request 3 makes this last change instead, if it
    merges later).

#### 7. `agent-skills/perennia/SKILL.md` (Modify)

The rule under [Agent surface](#agent-surface).

#### 8. Tests

`apps/mobile/test/domain/plan_logging_test.dart` (Create),
`apps/mobile/test/data/training_repositories_test.dart`,
`apps/mobile/test/features/training/training_screen_test.dart`,
`apps/mobile/test/performance/performance_budgets_test.dart` and its README
(Modify), per the Verification Plan.

**Gate:** `mobile`, `golden` (the change touches `apps/mobile/lib/domain`).

### Pull request 2: Progress (Problem 7)

#### 9. `apps/mobile/lib/features/home/repositories/home_repository.dart` (Modify)

The fields under [Progress](#progress-on-the-workout-screen-today-and-the-navigation-panel).

#### 10. `apps/mobile/lib/features/home/widgets/workout_screen.dart` (Modify)

Title, card counts and Done, round line, Now.

#### 11. `apps/mobile/lib/features/home/widgets/home_screen.dart` and `apps/mobile/lib/data/repositories/template_materialize_repository.dart` (Modify)

`home_screen.dart`: the tile segment. `template_materialize_repository.dart`:
`watchByWorkoutIds`. The day status line is item 9's
`_formatTrainingDayStatus`.

#### 12. `apps/mobile/lib/features/training/widgets/training_screen.dart` (Modify)

The Navigation Panel's counts and Now.

#### 13. `apps/mobile/lib/l10n/app_en.arb` (Modify), tests

New strings; `apps/mobile/test/features/home/home_repository_test.dart` and
the Workout screen and Today widget tests in the Verification Plan.

**Gate:** `mobile`.

### Pull request 3: Preview before start (Problem 8)

#### 14. `apps/mobile/lib/features/workout_templates/widgets/prescription_summary.dart` (Create)

`String prescriptionSummary(BuildContext, TemplateExerciseDetail,
PrescriptionDetail)`, moved from `_prescriptionSummary` with its unit label
helper; `workout_template_editor_screen.dart` calls it.

#### 15. `apps/mobile/lib/features/up_next/widgets/up_next_strip.dart` and `apps/mobile/lib/features/template_picker/widgets/template_picker_sheet.dart` (Modify)

Card body → preview, ▶ → start; Routines rows the same; the preview's
Prescription lines and group headers. New keys:
`UpNextStrip.startButtonKey(String routineId, String workoutTemplateId)` for
the card's ▶, and `TemplatePickerSheet.routineEntryStartKey(String
routineEntryId)` and `otherTemplateStartKey(String templateId)` for the rows'
▶. `UpNextStrip.cardKey`, `routineEntryTileKey` and `otherTemplateTileKey`
keep naming the card and rows (which now open the preview);
`routineEntryPreviewKey` and `otherTemplatePreviewKey` are deleted with the eye
icon.

#### 16. Tests

`apps/mobile/test/features/up_next/up_next_strip_test.dart` and
`apps/mobile/test/features/template_picker/template_picker_sheet_test.dart`.

**Gate:** `mobile`.

### Pull request 4: Replace (Problem 9)

#### 17. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

`WorkoutExerciseRepository.replace` and `AlreadyInWorkoutException`.

#### 18. `apps/mobile/lib/features/training/widgets/replace_exercise.dart` (Create)

`replaceExercise` as under [Replace an exercise](#replace-an-exercise). Add the
file to `l10n_externalization_test.dart`.

#### 19. `training_screen.dart` and `workout_screen.dart` (Modify)

The menu item and the card ⋮ button.

#### 20. `apps/mobile/lib/l10n/app_en.arb` (Modify), tests

Strings; repository and widget tests in the Verification Plan.

**Gate:** `mobile`.

## Verification Plan

### Gate jobs

*   Pull request 1: `node tools/ci-local.mjs mobile golden`.
*   Pull requests 2, 3 and 4: `node tools/ci-local.mjs mobile`.

### Domain (`plan_logging_test.dart`)

*   Current Set: first planned; picked planned; picked but performed falls
    back; none planned is null; tied positions order by id.
*   Carry-forward: the missing weight (CUJ 2); a missed rep (CUJ 3); a pyramid
    (CUJ 4); load unchanged carries nothing; a later Set with a different load
    untouched; earlier Sets untouched; rest carries only when changed and only
    to equal rests, nulls equal; a target already holding the values is left
    out; "60" against "60.0" differ; an exercise without load carries no load.
*   Next member: two members interleave; three wrap; a member without Planned
    Sets is skipped; none left is null (stay); a freestyle superset and a Set
    logged after the plan wrap to the next member; ungrouped is null; setting
    off is null.
*   Group round: equal counts; unequal counts; a member with no Sets left out;
    a replaced member (no Performed Set, same Sets left) keeps the round; all
    done; no Sets is null.
*   Rest shown: planned; remembered; 120 s; with no Current Set the last Set's
    rest, then remembered, then 120 s; zero is kept.
*   Current Exercise and next exercise: an in-progress exercise; an
    in-progress group; the group after a Replace (CUJ 13); moving on from a
    finished exercise; wrapping; no Performed Set; nothing planned.

### Repositories (in-memory SQLite)

*   `logSet` with a Current Set: values, annotations, `isCompleted`,
    `performedAt`; planned rest only when changed; carry targets; one entry per
    touched row; `undoBatch` restores every touched Set.
*   `logSet` on a completed or deleted Current Set returns `alreadyLogged` and
    writes nothing.
*   `logSet` without a Current Set creates a Performed Set at the next
    position.
*   `findRememberedRest`: latest by `performedAt`; null and zero rests
    skipped; incomplete Sets and deleted Workouts ignored; none is null.
*   `updatePerformed` writes one row; `adjust` extends, shortens, shortens past
    now, clears the prepare cue.
*   Divergence (CUJ 6): a Template with null rests, logged unchanged through
    `logSet`, gives no divergence.
*   Pull request 2: `templateName` (also an archived Template), performed
    counts, the day line.
*   Pull request 4: `replace` with `old` first, middle and last in 2- and
    3-member groups, with and without Performed Sets; values from history and
    the zero fallback; already in the Workout throws; one undo reverses it;
    the group survives a later reorder.

### Widgets

*   Pull request 1: CUJ 1, 2, 5, 7, 8, 9, 10 on the Training Screen: rows, form
    values and units, button labels, the confirmation texts and Undo (which
    also cancels the started timer), the rest start, the move to the next
    member; a double tap logs once; an extra Log set after a 0 s plan starts
    no timer and leaves the button usable; a hard reject shows "Set not
    logged"; a reload by sync keeps a stepped but unsaved value; Update mode
    survives a sync and ends when its Set is un-completed elsewhere; a kg plan on an
    imperial unit setting logs kg; Log set on an ended Workout starts no timer;
    the rest strip's adjust and Stop; accessibility (48 dp, row semantics,
    text scale 2.0 with the strip and buttons visible).
*   Pull request 2: CUJ 11 on the Workout screen and Today; the Navigation
    Panel's counts and Now.
*   Pull request 3: CUJ 12; Routines rows; the preview's Prescription lines.
*   Pull request 4: CUJ 13 from the Training Screen and the Workout screen;
    "Already in this workout".

### Kill and reopen

CUJ 14: log Set 2 of 3 against a file database, close and reopen it, rebuild
the screen: Set 3 is current, the round line is right, the rest resumes from
its deadline.

### By hand

On the Android emulator, replay the reproduction in
[The Problem](#the-problem) after each pull request: each problem it covers is
gone; after pull request 1 the rest sticks across Log set and the superset
walks A1, B1, A2, B2.
