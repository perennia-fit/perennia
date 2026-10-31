# Progress Overview

*   **Author:** Leonardo Pinheiro
*   **Status:** Draft
*   **Date:** 2026-10-31

--------------------------------------------------------------------------------

## Overview

Perennia's root navigation is **Today | Progress | Library**. The Progress
root currently shows only two links: **Body** (the Body Tracker) and **Health
metrics** (the Metrics explorer). Most of the app's progress views already
exist, but they sit elsewhere:

*   per-exercise graphs and records live in Exercise Overview, reached only
    from an exercise;
*   protocol consistency and Effect live inside each Compound and Protocol,
    behind the Protocols lock;
*   nothing shows whether the user trained as their Routine planned this week,
    even though a Routine's Cadence and each Workout's Template Link hold
    enough data to derive it.

This spec turns the Progress root into **Progress Overview**: one scroll of
summary cards, each derived from data the app already records and each opening
a detail screen that already exists. It answers three questions in order:

1.  **Am I showing up?** This week's plan against what was done, the Trained
    Days in the period, and the time trained each week per Focus.
2.  **Am I getting better?** Small charts for the user's key exercises, and a
    list of new bests across all exercises.
3.  **How is my body responding?** A smoothed trend over each Body Tracker
    measurement, with the raw readings underneath, and, while Protocols are
    unlocked, the protocol consistency counts for the same period.

It adds one authored field, a **color** on each Focus, so time trained can be
stacked by Focus. Everything else is computed on read and never stored.

The terms used here are defined in [CONTEXT.md](../../CONTEXT.md). How the
app is layered, and what is generated from what, is in
[ARCHITECTURE.md](../../ARCHITECTURE.md). The rules every change must keep are
in [AGENTS.md](../../AGENTS.md#non-negotiable-invariants). Visual tokens and
component rules are in [DESIGN.md](../../DESIGN.md). The protocol consistency
rules this spec reuses are in
[Protocol Schedules and Reminders](protocol-schedules-and-reminders.md).

### Product rules this spec keeps

These come from the product's voice (plain, factual, instrument-like; no
motivational copy; no celebration beyond a personal-record marker) and from
the Protocols spec's rejection of scores and streaks
([Alternative N](protocol-schedules-and-reminders.md#alternative-n-a-consistency-score-or-streak-d6)).
This spec applies them to training too:

*   **Counts and statuses, never scores.** No percentage, streak, ring or
    grade, and the word "missed" is never used. A planned day that passed
    without a Workout is "Not done".
*   **Direction without judgment.** A change shows an arrow or a word and an
    amount in the secondary text color. Red stays for destructive actions.
    Trophy Gold appears only with the trophy glyph, as DESIGN.md requires.
*   **Raw data under every trend.** A smoothed line is always drawn over the
    readings it came from.
*   **Descriptive, never causal.** Nothing on Progress says what worked.
*   **The lock covers Progress.** No Compound or Protocol name appears on
    Progress while Protocols are locked, and the locked card does not reveal
    whether any Protocol exists.

### Decisions already made

The product owner settled these before and during review:

*   training follows the Protocols no-score rule;
*   key exercises are the user's existing **Favorites**;
*   Focus gets a color the user can change;
*   protocol counts appear on Progress, behind the lock;
*   plan against done covers **the current week only**. Earlier weeks show the
    days trained, with no plan comparison, because Routines keep no history of
    their plan (see [Alternative A](#alternative-a-compare-past-weeks-with-the-plan)).

## The Problem

The people Perennia is for train across several disciplines (strength,
endurance, mobility) for long-term health. They plan their week with Routines,
take protocols, and track body composition. After a few weeks they want to
know three things: whether they are showing up, whether they are getting
stronger and faster, and how their body is changing.

Each answer currently takes several screens:

*   **Following the plan.** The only plan signal is Up next's "done" tick for
    today's slot. Nothing shows the rest of the week.
*   **Showing up over time.** Nothing counts the days trained across weeks.
*   **Balance across disciplines.** Nothing totals training time. A
    strength-only volume chart cannot compare a long run with a lifting
    session, but every Workout has a start and an end, so time can.
*   **Getting better.** Exercise Overview shows one exercise at a time and is
    reached only through that exercise. Nothing lists the records set this
    month.
*   **Body.** Body Tracker plots raw readings. Daily weight moves by a
    kilogram or more with water and food, so the raw line hides the real
    direction.
*   **Protocols.** Consistency is per Compound, two levels deep inside the
    Protocols area.

## Goals

1.  Progress Overview replaces the Progress root's two links with summary
    cards, in this order: This week, Trained days, Time by Focus, Key
    exercises, New bests, Body, Protocols, then the existing links to Body
    Tracker and Health metrics.
2.  One period control (4 weeks, 12 weeks, 1 year) sets every card except
    This week.
3.  **This week card:** a Training Day Status for each day of the current
    week against the active weekly Routines, with counts per status.
4.  **Trained days card:** a calendar of the Trained Days in the period, and
    their count.
5.  **Time by Focus card:** weekly time per Focus as stacked bars.
6.  **Key exercises card:** one small chart per Favorite exercise, plotting
    its Progress Measure per Workout.
7.  **New bests card:** the count of New Bests in the period across all
    exercises, and the five most recent.
8.  **Body card:** each curated Body Tracker measurement with its Trend line
    over its raw readings.
9.  **Protocols card:** per Compound, the Day Status counts for the period.
    While a Protocols lock is set and locked, the card shows only the lock.
10. Focus gains a color the user can change in the Focus manager.
11. Each card's app release includes the Agent read that returns the same
    numbers. Every computation an Agent read returns has a shared Dart and
    TypeScript core pinned by golden vectors.

## New and changed terms

Each lands in [CONTEXT.md](../../CONTEXT.md) in the implementation pull
request that first uses it (see the Detailed Implementation Plan).

*   **Performed Set** (new). A Set that is not deleted, belongs to a Workout
    that is not deleted, and is marked complete. Saving a Set on the Track tab
    marks it complete. A Set that a Workout Template or a quick log placed in
    a Workout stays incomplete until the user completes it. On the server, a
    Set payload without `is_completed` is not performed, matching how the app
    decodes it.
*   **Logged Workout** (new). A Workout that is not deleted and has at least
    one Performed Set. A Workout started from Up next and abandoned holds only
    incomplete Sets, so it is not a Logged Workout. Only Logged Workouts count
    toward Training Day Statuses, Trained Days and time by Focus.
*   **Training Day Status** (new). The single label for one day of the current
    week against the user's weekly Routines, from a closed set: Done, Partly
    done, Done differently, Not done, Pending, Planned, Trained, Rest, or No
    plan. Derived, never stored; never a score, a streak or a percentage.
    Mirrors Day Status in the Protocols domain.
*   **Trained Day** (new). A Training Day (in CONTEXT.md, the Workouts that
    share one local date) with at least one Logged Workout.
*   **Progress Measure** (new). The single number per Workout that shows
    whether an exercise is improving, chosen by its Record Profile: estimated
    one-rep max for rep-max exercises, otherwise the value of that profile's
    record (heaviest load, most reps, longest or shortest duration, longest
    distance, fastest pace). It is the best value among the Workout's
    Performed Sets. Derived, never stored.
*   **New Best** (new). A Workout whose Progress Measure for an exercise is
    strictly better than every earlier Workout's value for that exercise. The
    exercise's first Workout with a value is never a New Best. Derived, never
    stored.
*   **Trend** (new). The smoothed series over a Metric's scalar Readings: an
    exponentially weighted average whose weight grows with the time between
    Readings (see [D5](#d5-trend)). Derived, never stored, and always drawn
    over the raw Readings.
*   **Focus** (changed). Adds: "A Focus has a color, used wherever training is
    colored by Focus. Until the user picks one, the color comes from a fixed
    default for the Focus."

This spec says **Open Workout** for any Workout whose `endedAt` is null.
CONTEXT.md's Open Session is the narrower case of the current Training Day's
Workout; no CONTEXT.md entry changes for this.

## Non-Goals

*   **Plan comparison before the current week.** Earlier weeks show Trained
    Days only (see [Alternative A](#alternative-a-compare-past-weeks-with-the-plan)).
*   **Comparisons across domains.** Protocol periods drawn as bands over
    performance and body charts, stacked panels on one time axis, and
    before/during/after from a chart tap are the next phase. This spec makes
    no change to Effect.
*   **Nutrition on Progress.** Intake against the weight Trend waits for the
    nutrition logging work.
*   **Tracker data.** Resting heart rate, HRV, sleep lanes and training load
    wait for tracker integrations.
*   **Rotating Cadences in the plan comparison.** A rotating Cadence waits
    when the user skips, so it never plans a date. Its Workouts show as
    Trained.
*   **Carrying a planned workout to another day.** Matching is by date. A
    session started after midnight belongs to the next date, as everywhere
    else in the app ([CUJ 4](#cuj-4-a-session-after-midnight)).
*   **Changing Up next.** Up next keeps its own done tick
    ([D1](#d1-training-day-status-this-week) explains the difference).
*   **Weekly sets per Category.** Left for later.
*   **New settings.** The period choice is not persisted.
*   **Changes to Body Tracker, Health Metrics, Exercise Overview, Consistency
    or Effect screens.** Progress Overview links to them as they are. The
    Trend and the Progress Measure therefore appear only on Progress; the
    detail screens keep showing raw readings and records. Adding them there
    is a separate change.
*   **Fixing incomplete Sets in Exercise Overview.** Exercise Overview's
    records currently include incomplete Sets. Progress uses Performed Sets
    only; Exercise Overview is unchanged here (see
    [Risks](#risks-and-mitigations)).
*   **Agent access to Focus color.** Agents read no Category color today, and
    Focus follows that precedent.

## Open Questions

None. The product decisions are recorded in
[Decisions already made](#decisions-already-made).

## Critical User Journeys (CUJs)

The examples use a week starting Monday (the default `weekStartDay`), the
metric unit system, and one weekly Routine "Hybrid block": Monday "Lower",
Tuesday "Run intervals", Thursday "Upper", Saturday "Long run". The current
week runs from Monday 26 October to Sunday 1 November 2026.

### CUJ 1: Checking the week

*   **Given** it is Sunday 1 November at 18:00. This week the user did
    "Lower" on Monday (started from Up next), "Run intervals" on Tuesday, a
    Workout with no template on Wednesday, nothing on Thursday, and on
    Saturday a Workout from the saved workout "Easy spin" instead of "Long
    run".
*   **When** they open Progress.
*   **Then** This week reads: Monday Done, Tuesday Done, Wednesday Trained,
    Thursday Not done, Friday Rest, Saturday Done differently, Sunday Rest. Its
    summary reads "2 done · 1 done differently · 1 not done · 1 trained".

### CUJ 2: Today is not over

*   **Given** it is Thursday 29 October at 09:00. Thursday plans "Upper"
    only. The user did an unplanned morning run.
*   **When** they open Progress.
*   **Then** Thursday is Pending and is not counted in the summary. Saturday
    is Planned. Once they complete a Set in a Workout started from "Upper"
    that evening, Thursday is Done.

### CUJ 3: A rotating Routine

*   **Given** the user's only Routine has a rotating 4-day Cadence.
*   **When** they open Progress.
*   **Then** This week shows every day with a Logged Workout as Trained and
    every other day as No plan, and says "Weekly Routines only". Nothing is
    Not done.

### CUJ 4: A session after midnight

*   **Given** the user planned "Lower" on Monday and started it at 00:30 on
    Tuesday.
*   **When** they open Progress on Wednesday.
*   **Then** Monday is Not done and Tuesday is Done differently, because the
    Workout's date is Tuesday. This matches Today, which shows that Workout on
    Tuesday.

### CUJ 5: An abandoned planned workout

*   **Given** on Tuesday the user tapped "Run intervals" in Up next, which
    placed its prescribed Sets in a new Workout, and left without completing
    any Set.
*   **When** they open Progress on Wednesday.
*   **Then** Tuesday is Not done, Tuesday is not a Trained Day, and the
    Workout adds no time to Time by Focus.

### CUJ 6: Showing up over 12 weeks

*   **Given** the user trained on 41 dates in the last 12 weeks.
*   **When** they look at Trained days with 12 wk selected.
*   **Then** the card reads "41 trained days" over a calendar with one
    filled cell per Trained Day, and an outlined cell for every other past
    date.

### CUJ 7: Balance across disciplines

*   **Given** this week the user logged 160 minutes under Weights, 190 under
    Endurance and 35 under Mobility, and one 20-minute Workout with no Focus.
*   **When** they look at Time by Focus.
*   **Then** this week's bar stacks those four amounts, the legend reads
    "Weights 2h 40m · Endurance 3h 10m · Mobility 35m · No Focus 20m", and
    every week's bar uses the same scale.

### CUJ 8: Recoloring a Focus

*   **Given** the user created a Focus "Climbing".
*   **When** they open the Focus manager, choose Color on "Climbing" and pick
    a swatch.
*   **Then** "Climbing" uses that color in Time by Focus on every synced
    device, and the change is in the Activity Log. Reordering Focuses never
    changes any Focus's color.

### CUJ 9: A new best on a run

*   **Given** "5 km run" has Record Profile fastest pace and is a Favorite.
    Before this period their fastest was 5:22 per km. On Saturday they ran
    5:04 per km.
*   **When** they open Progress.
*   **Then** the "5 km run" tile reads "Best 5:04 /km" with "18 s faster than
    before", its Saturday point has a New Best marker, and New bests lists
    "5 km run · 5:04 /km · Sat" at the top with the trophy glyph.

### CUJ 10: No Favorites yet

*   **Given** the user has marked no exercise as a Favorite.
*   **When** they open Progress.
*   **Then** the Key exercises card shows one line, "Mark exercises as
    favorites to chart them here", with no action, because the app has no
    standalone exercise list to open.

### CUJ 11: A noisy scale

*   **Given** the user weighs in most mornings, with readings swinging
    between 80.4 and 81.9 kg over two weeks.
*   **When** they look at the Body card.
*   **Then** Body Weight shows the readings as dots in the secondary text
    color and the Trend as a line in the accent color, labelled with the
    latest Trend value and its change over the period.

### CUJ 12: Protocols locked

*   **Given** the user has a Protocols lock and `showProtocolsOnToday` on.
*   **When** they open Progress after the app was in the background.
*   **Then** the Protocols card shows only a lock row and an Unlock button,
    whether or not any Protocol exists. After unlocking, the card lists each
    Compound with a counted Day Status in the period, with its counts, for example "Creatine ·
    26 logged · 2 not logged", and tapping a row opens its Consistency view.

### CUJ 13: An Agent asks about the week

*   **Given** the user's Agent is asked "Did I follow my plan this week, and
    how often did I train in October?"
*   **When** it calls `agent_list_training_days` with `fromLocalDate`
    2026-10-01, `toLocalDate` 2026-10-31 and `today` 2026-11-01.
*   **Then** it receives the same Trained Days, time per Focus and this
    week's statuses that the app shows for those dates.

### CUJ 14: First run

*   **Given** a new install with no Workouts, Routines or readings.
*   **When** the user opens Progress.
*   **Then** each card shows its one-line empty state and at most one action.
    There is no Protocols card while the lock is off and nothing is planned.

## Technical Plan

### Shape of the change

Three cores are written once in Dart (`apps/mobile/lib/domain`) and once in
TypeScript (`apps/server/src/analytics`), pinned by golden vectors, because
an Agent read returns their results:

| Core | Functions | Vectors |
| :--- | :-------- | :------ |
| Training progress ([D1](#d1-training-day-status-this-week), [D2](#d2-trained-days), [D3](#d3-time-by-focus)) | `trainingWeek`, `summarizeTrainingWeek`, `trainingDays` | `m37-training-progress.json` |
| Progress Measure ([D4](#d4-progress-measure-and-new-bests)) | `progressSeries`, `newBestsBetween` | `m37-progress-measure.json` |
| Trend ([D5](#d5-trend)) | `metricTrend` | `m37-metric-trend.json` |

Four small computations live only in Dart, with unit tests, because no Agent
read returns them: `weeklyFocusSeconds` ([D3](#d3-time-by-focus)),
`periodBest` ([D4](#d4-progress-measure-and-new-bests)), `trendChange`
([D5](#d5-trend)) and `focusDefaultColorToken` ([D6](#d6-focus-color)). An
Agent can derive the first three from what it reads.

The Protocols card reuses the existing `planDays` and `dayStatuses` cores
unchanged ([D7](#d7-protocols-card)).

The app reads its inputs through one feature repository, runs the cores in
providers, and renders cards ([D8](#d8-the-progress-overview-screen)). Agents
get two new read operations and two additions to existing reads
([D9](#d9-agent-surface)). The only schema change is the nullable column
`Focuses.colorHex` ([D6](#d6-focus-color)).

### D0. Performed Sets and Logged Workouts

Every input to the training progress and Progress Measure cores is built from
Performed Sets: Sets with `deletedAt` null and `isCompleted` true whose
Workout has `deletedAt` null. There are no cascading deletes, so a deleted
Workout's Sets stay undeleted; the loaders drop them by joining to the
Workout, as `ExerciseAnalyticsRepository` already does through
`_activeWorkoutsById`. The
codebase already uses this rule for copy-previous values and volume samples
(`_lastPerformedValuesByExerciseId` in `template_materialize_repository.dart`,
and `performanceVolumeSamples`). The cores make the rule testable:

*   `ProgressWorkout` carries `performedSetCount`. `trainingWeek` and
    `trainingDays` ignore a Workout whose `performedSetCount` is 0.
*   `ProgressSet` carries `isCompleted`. `progressSeries` ignores a Set whose
    `isCompleted` is false.

The loaders fill these fields the same way in both languages, and a vector
case covers each field. In the app,
`is_completed` is a column with default `false`. On the server it is the Set
payload's `is_completed`, where a missing key means `false`. Every app and
Agent writer already writes the key, so this only matters for malformed
payloads. The server's existing exercise analytics read keeps its own
`is_completed ?? true` reading, which this spec does not change.

### D1. Training Day Status (this week)

**Inputs** to `trainingWeek`:

*   `plans`: one entry per active Routine whose Cadence is weekly:
    `{routineId, entries: [{workoutTemplateId, weekday}]}`. `weekday` is ISO,
    1 = Monday to 7 = Sunday, from `RoutineEntries.slot`. An entry plans
    nothing when its slot is null, the entry is archived, or its Workout
    Template is archived, the same rule Up next applies. The loaders drop
    those entries. The core ignores a plan with no entries, so a weekly
    Routine with no planning entries plans nothing in either language.
*   `workouts`: `ProgressWorkout` facts for every Workout whose `localDate`
    is in the week: `{workoutId, localDate, startedAt, endedAt?, focusId?,
    linkedTemplateId?, performedSetCount}`. `linkedTemplateId` is the
    `workoutTemplateId` of the Workout's Template Link. When a Workout has
    more than one active Template Link, the loaders take the one with the
    latest `updatedAt`, then the highest `id`. CONTEXT.md allows at most one
    Template Link per Workout, but neither the schema nor sync enforces it, so
    this rule is defensive. Open Workouts are included.
*   `weekStart`: the local date the current week begins.
*   `today`: a local date in `[weekStart, weekStart + 6]`; otherwise the core
    throws an argument error (Dart `ArgumentError`, TypeScript `RangeError`).

The core ignores any Workout whose `localDate` is outside the week, so a
caller may pass a wider list.

The caller computes `weekStart` from `today` and the week start setting
(`AppSettings.weekStartFor(today)` in the app; the account's synced
`weekStartDay` on the server). The core takes a date, not the setting, so it
needs no settings type.

**Planned entries for date `d`.** For each plan, the entries whose `weekday`
equals `d`'s ISO weekday. A Workout Template planned by two Routines on the
same day is two planned entries.

**Matching.** Planned entries are ordered by `(routineId, workoutTemplateId)`
and Logged Workouts by `(startedAt, workoutId)`. Each planned entry, in order,
takes the first unmatched Logged Workout of that date whose
`linkedTemplateId` equals its `workoutTemplateId`. A Workout matches at most
one entry.

Matching is by template and date, not by the Template Link's Routine and slot.
A planned workout started from the saved-workouts list counts as Done. Up next
ticks its card only when the link carries that Routine and slot. For a workout
started outside Up next the two can therefore differ on the same day: Up next
answers "did I start this slot", Progress answers "did I do the planned
workout".

**Status.** For date `d`, let `p` be the number of planned entries, `m` the
number matched, and `w` the number of Logged Workouts. Rows are checked top to
bottom; the first that holds applies. The Status column gives the Dart
`TrainingDayStatus` value names; their wire values follow the table.

| Condition | Status |
| :-------- | :----- |
| `p > 0` and `m = p` | `done` |
| `p > 0`, `m < p`, `d = today` | `pending` |
| `p > 0`, `d > today` | `planned` |
| `p > 0`, `0 < m < p`, `d < today` | `partlyDone` |
| `p > 0`, `m = 0`, `w > 0`, `d < today` | `doneDifferently` |
| `p > 0`, `w = 0`, `d < today` | `notDone` |
| `p = 0`, `w > 0` | `trained` |
| `p = 0`, `w = 0`, at least one plan has entries | `rest` |
| `p = 0`, `w = 0`, no plan has entries | `noPlan` |

**Wire values.** Statuses are snake_case on the wire, in vectors and in the
API, as the Protocols Day Statuses are (`partly_logged`): `done`,
`partly_done`, `done_differently`, `not_done`, `pending`, `planned`,
`trained`, `rest`, `no_plan`. The Dart `TrainingDayStatus` enum carries each
wire value as a field, as `DayStatusKind` does.

**Output.** `trainingWeek` returns `{weekStart, days, comparedRoutineIds}`.
`days` holds seven entries in date order, each `{localDate, status,
plannedCount: p, matchedCount: m, workoutCount: w}`. `comparedRoutineIds`
lists the ids of the plans with entries, ascending.

**Counts.** `summarizeTrainingWeek(days)` returns the number of days with each
of `done`, `partly_done`, `done_differently`, `not_done` and `trained`, as
the fields `done`, `partlyDone`, `doneDifferently`, `notDone` and
`trained`. The other
statuses are not counted. Because `pending` covers today until it is Done, an
unfinished today is never counted.

**Accepted limitation.** The week is compared with the plan as it is now. If
the user moves "Upper" from Thursday to Friday on Friday, Thursday stops being
planned and Friday is compared with "Upper". Routines keep no plan history, so
nothing can say what the plan was on Thursday
([Alternative A](#alternative-a-compare-past-weeks-with-the-plan)).

### D2. Trained Days

**`trainingDays(workouts, from, to)`** takes `ProgressWorkout` facts for the
range and two inclusive local dates, with `from <= to` and at most 366 dates
in the range; otherwise the core throws an argument error. Workouts whose
`localDate` is outside the range are ignored. It returns one entry per date,
ascending: `{localDate, workoutCount, secondsByFocus}`. `workoutCount`
counts Logged Workouts, Open Workouts included. `secondsByFocus` is defined
in [D3](#d3-time-by-focus).

**Trained Days in the period** are the entries with `workoutCount > 0` and
`localDate <= today`.

### D3. Time by Focus

A Logged Workout's time is `endedAt - startedAt` in whole seconds
(truncated), or 0 when `endedAt` is before `startedAt`. `secondsByFocus` maps
a Focus id, or the key `"none"` for Workouts without a Focus, to the summed
seconds of that day's ended Logged Workouts. A key is present when at least
one ended Logged Workout that day has that Focus, even if its time is 0. An
Open Workout adds no time and no key. A date
without Logged Workouts has an empty map. Archived Focuses keep their time
and name. A Workout counts toward its `localDate`, even if it crosses
midnight.

**`weeklyFocusSeconds(days, firstWeekStart)`** (Dart only) sums the per-date
seconds into consecutive seven-day buckets starting at `firstWeekStart`, the
period's first date. The display rounds each (week, Focus) amount half up to
whole minutes once, so an Agent summing the per-date seconds gets the same
amounts.

### D4. Progress Measure and New Bests

**`progressSeries(exerciseId, profile, workouts)`** takes the exercise's
profile (dimensions, load mode, Record Profile) and its Sets grouped by
Workout, as `ProgressWorkoutSets {workoutId, localDate, startedAt, sets:
ProgressSet[]}` with `ProgressSet {id, position, isCompleted, values}`.
`values` is the engine's existing logged-values shape. It returns
`ProgressSeries {exerciseId, measure, betterIs, points}`, or null for the
profiles in the last row of the table below.

**Which exercises.** Progress Measures and New Bests cover active exercises
only, in both languages. In the app, an exercise is active when its
`Exercises` row has `deletedAt` null, which is the rule
`ExerciseAnalyticsRepository` already applies. On the server, it is an
exercise that `AgentCatalogStore.getExercisesByIds` returns with `active`
not false. An archived exercise's Workouts still count toward Training Day
Statuses, Trained Days and time.

**How the measure is taken.** For each Workout, drop Sets that are not
Performed, then run the existing engine (Dart
`ExerciseAnalyticsEngine.compute`; TypeScript `new
ExerciseAnalyticsEngine().compute` in `analytics/exercise-analytics.ts`) over
that Workout's remaining Sets. Each Set is passed with `performedAt` set to
the Workout's `startedAt` and its sequence set to `position`. A Workout with
no Performed Set, or whose result has no value for the measure, yields no
point. The engine is called, not changed, so its normalization applies and
nothing is extracted from it.

| Record Profile | `measure` | Value taken from the per-Workout result | `betterIs` |
| :------------- | :-------- | :-------------------------------------- | :--------- |
| `repMax` | `estimatedOneRepMax` | the highest point of `estimatedOneRepMax` | `higher` |
| `maxLoad`, `maxReps`, `maxDuration`, `maxDistance` | same as the profile | `headlineRecord` | `higher` |
| `minDuration`, `fastestPace` | same as the profile | `headlineRecord` | `lower` |
| `minAssistancePerRepCount`, `completionStreak` | none | no series | none |

When two `estimatedOneRepMax` points have the same value, the point from the
Set with the lower `(position, id)` is used. `minAssistancePerRepCount` is a
record per rep count, so no single number would agree with the engine, and it
gets no series. A `repMax` exercise in assisted load mode has no estimated
one-rep max, and its series has no points. Values and `unit` are the engine's
normalized ones: kilograms, kilometres, seconds, and seconds per kilometre
for pace, whose `unit` is `second`. On the wire, `unit` is the
`TrainingUnit` name (`kilogram`, `repetition`, `second`, `kilometer`).

A point is `{workoutId, localDate, startedAt, setId, value, unit,
isNewBest}`. `setId` is the Set the engine's value came from.

**New Best.** Points are ordered by `(localDate, startedAt, workoutId)`. A
point is a New Best when its value is strictly better than every earlier
point's value, compared exactly. The first point is never a New Best; equal
values are not New Bests.

**New bests in a period.** `newBestsBetween(series, from, to)` takes a list of
series and returns every New Best point whose `localDate` is in `[from, to]`
as `NewBest {exerciseId, measure, ...the point's fields}`. The order is by
`localDate` descending, then `startedAt` descending, then `workoutId`
descending, then `exerciseId` ascending. Series are built over each
exercise's whole history, so a best is judged against everything before it.

**Period best** (Dart only). `periodBest(series, from, to)` returns `best`,
the best point whose `localDate` is in the period, and `bestBefore`, the best
value among points before `from`. Either can be null. On equal values the
earlier point is the best. The Key exercises tile shows these two.

### D5. Trend

**Inputs.** A Reading takes part when it is live (not archived or deleted)
and has a scalar value: its `scalarValue`, or else a numeric `value` key in
its `valueJson`. This is the rule the app's `_metricReadingScalarValue`
already applies, and the server applies the same rule. Its `at` is
`atTime ?? windowStartedAt ?? updatedAt` on both sides. That is the rule
Body Tracker uses for a measurement entry's time, and it deliberately
differs from the server readings list's sort key, which also considers
`windowEndedAt`. In the app the inputs are mapped from the
`MeasurementHistoryEntry` records that Body Tracker reads.

`metricTrend(readings)` takes `{id, at, value}` points, sorts them by
`(at, id)`, skips any whose value is null or not finite (a skipped point has
no Trend point), and returns `{id, at, value, trend}` for each remaining
point:

*   the first Trend value equals the first Reading's value;
*   each later one is `trend[i] = trend[i-1] + a * (value[i] - trend[i-1])`
    with `a = 1 - 0.9 ^ days`, where `days` is the time since the previous
    kept Reading in fractional days (milliseconds / 86 400 000).

With one Reading a day, each new Reading moves the Trend 10% of the way
towards it. The Trend therefore follows a lasting change within about two
weeks while a single day's water swing moves it little. Readings several days
apart move it further; two Readings minutes apart barely move it. The card's
Trend label has the hint "Smoothed over about 10 days".

The Trend is computed over the Metric's whole history and then clipped to the
period. Readings are not converted between units.

**Change over the period** (Dart only). `trendChange(points, start, end)`
takes two instants: `start`, the beginning of the period's first local day in
the device's zone, and `end`, the beginning of the day after its last. The
result is the Trend at the last point before `end` minus the Trend at the last
point before `start`. When no point comes before `start`, the Trend at the
first point at or after `start` is used instead. When the period has no point,
the result is null.

The vectors compare Trend values with an absolute tolerance of 1e-9, because
`pow` can differ in the last bit between Dart and JavaScript.

### D6. Focus color

**Stored.** `Focuses` gains `colorHex`, nullable text in `#RRGGBB` form. Null
means "use the default". The sync payload key is `color_hex`.

**Kept when absent.** A device without this change pushes Focus payloads
without `color_hex`. Three places together stop that from erasing a
color:

*   **Device decode.** A missing key leaves the column as it is, and an
    explicit null clears it. This follows the existing `_imageFocusId`
    pattern.
*   **Server carry-forward.** `SYNC_CARRY_FORWARD_PAYLOAD_KEYS` in
    `apps/server/src/sync.ts` gains `[FOCUSES_SYNC_ENTITY]: ["color_hex"]`.
    Focuses are pushed through `pushAccountKeyedSyncRowsInTransaction`, whose
    shared `readExisting` does not select `payload`, so carry-forward would
    find nothing stored. That `readExisting` therefore also selects
    `payload`. The other entities pushed through it (exercise categories,
    meal types, compounds) read the extra column but carry nothing forward,
    because they have no entry in the map.
*   **Undo.** `_activityImagesEqualForEntity` in `training_repositories.dart`
    treats a Focus image without `color_hex` as equal to one whose
    `color_hex` is null. Undo of an Activity Log entry written before the
    upgrade therefore still finds its image current.

**Default.** `focusDefaultColorToken(focusId)` (Dart only) returns a DESIGN.md
category token key, never a hex value:

*   the starter Focuses map by id: Weights to `back`, Endurance to `cardio`,
    Functional to `shoulders`, Calisthenics to `arms`, Mobility to `core`;
*   any other Focus maps to `[back, cardio, core, shoulders, arms, legs,
    chest][fnv1a32(focusId) mod 7]`, where `fnv1a32` is the 32-bit FNV-1a hash
    of the id's UTF-8 bytes.

The starter ids are the keys of the `_starterFocusIcons` map in
`focus_visuals.dart`:

| Starter | Id |
| :------ | :- |
| Weights | `01910000-0000-7000-8000-000000000401` |
| Endurance | `01910000-0000-7000-8000-000000000402` |
| Functional | `01910000-0000-7000-8000-000000000403` |
| Calisthenics | `01910000-0000-7000-8000-000000000404` |
| Mobility | `01910000-0000-7000-8000-000000000405` |

They move into `focus_color.dart` as constants, and the icon map uses them.
`other` is never a default and is not offered for a Focus, because "No
Focus" uses it in Time by Focus. The default depends only on the id, so reordering
never recolors a Focus. Two user Focuses can share a default color; the user
can change either.

`resolvedFocusColor(FocusRecord focus, AppColors colors)` in
`focus_visuals.dart` returns `colorFromHex(focus.colorHex, fallback:
colors.categoryColor(focusDefaultColorToken(focus.id)))` when a color is
stored, and the default token's color otherwise. The category colors are the
same in both themes (`DesignTokens.category`), so a stored hex means the same
color in light and dark. No hex value is hard-coded in widgets, and domain
records stay free of Flutter imports.

**Edited.** The Focus manager's row menu gains **Color**. It opens a dialog
titled "Color for {name}" with seven swatches, in this order: back, cardio,
core, shoulders, arms, legs, chest. Each swatch's hex is
`colorToHex(DesignTokens.category[token])`, and its label is the token's
name ("Back", "Cardio" and so on). The selected swatch is `colorHex`, or the
hex of the default token when `colorHex` is null. The dialog has a Cancel
button. Choosing a swatch closes the dialog and calls
`FocusRepository.recolor`. There is no Default option: once the user picks a
swatch, the Focus keeps a stored hex, and picking the default token's swatch
stores that token's hex. Because category colors are the same in both themes,
this looks the same as the default. Only a sync image with an explicit null
clears the column.

`colorToHex(Color)` is the private `_colorToHex` in
`workout_template_editor_screen.dart`, promoted to `app_colors.dart` next to
`colorFromHex`. The template editor then uses the shared one.

The swatch row is extracted from `category_manager_screen.dart` into a shared
`ColorSwatchRow` that keeps today's behavior:
*   each swatch is an `IconButton` whose tooltip and semantics label is the
    option's `label`;
*   the selected swatch is disabled, so tapping it does nothing.

The Category manager passes its existing palette with the labels it uses
today ("Use #RRGGBB", not localized, unchanged) and its existing keys.

`recolor` to the color already stored writes nothing and appends no
Activity Log entry, as `rename` does for an unchanged name.

`recolor` normalizes the hex with the existing `_normalizeColorHex`, which
`focus_repository.dart` can already call because it is a `part of`
`training_repositories.dart`. It writes the row, appends an Activity Log
entry and syncs like a rename. Like `rename`, it works on an archived Focus,
so past time keeps the user's color, and fails only on a missing one through
`_requireRow`.

**Validated.** `_normalizeColorHex` throws `ArgumentError` on anything other
than `#RRGGBB` (case-insensitive, stored upper-case). This is rule
`focus_color_hex`, a hard reject in the app only, like Category color, because
no Agent operation sets a Focus color. An Agent undo can write back an earlier
Focus image, but that image came from a validated write.

**Archived.** The portable archive serializes rows with `toJson`, so new
archives carry `colorHex`. Reading an archive from schema 62 or earlier
leaves `colorHex` null: the generated `fromJson` reads a missing nullable
field as null.

### D7. Protocols card

The card follows `AppSettings.showProtocolsOnToday`. A user who hides
Protocols from Today has hidden them from the main surfaces, so the card is
absent when that setting is off. Otherwise it watches
`protocolsLockControllerProvider`:

*   **Loading:** nothing renders, because the card may turn out absent.
*   **Locked:** one row with a lock icon, "Protocols are locked", and an
    Unlock button that opens the existing `ProtocolsUnlockForm` in a bottom
    sheet.
*   **Unavailable or error:** one row with a lock icon and the existing
    `protocolsLockUnavailableTitle` text, with no button, as the Protocols
    Today view does.

    Both the locked and the unavailable row look the same whether or not any
    Protocol exists, so the card reveals nothing, and an error fails closed.
*   **Unlocked, or no lock set:** one row per Compound with at least one
    counted status in the period, ordered by Compound name
    (case-insensitive), then by id. Each row shows
    the Compound name and its non-zero counts of `logged`, `partlyLogged`,
    `notLogged` and `paused`, in that order, for example "26 logged · 2 not
    logged". `pending`, `offCycle` and `notPlanned` are not counted.
    *   At most six rows show. When there are more, an "All protocols" text
        button under the rows switches to Today with the Protocols tab
        selected: it sets `selectedHomeDestinationProvider` to `today` and
        `selectedHomeDomainProvider` to `HomeDomain.protocols`.
    *   Tapping a row pushes `ProtocolsLockGate(child:
        ConsistencyScreen.compound(compoundId: …, compoundName: …))`, as
        `compound_list_screen.dart` does, with the screen's own default
        range. The Consistency screen is not changed.
    *   With no lock set and no counted rows, the card is absent.
    *   With a lock set, unlocked, and no counted rows, the card shows "No
        protocol days in this period", with no action. It is not absent, so
        unlocking never reveals whether Protocols exist by making the card
        disappear.

The counts come from a new repository read,
`ProtocolPlanRepository.watchConsistencySummary(from, to, today: today)`,
which takes `ProtocolDayDate`s. Progress converts its `TrainingDayDate`s field
by field (`ProtocolDayDate(year: d.year, month: d.month, day: d.day)`). It runs the
existing `planDays` and `dayStatuses` over every Protocol, archived ones
included, loaded through the same `_planQuery()` that `watchConsistency`
uses, then counts per Compound. It therefore agrees with the Consistency view
and with the Agent's day statuses. The 1-year period (364 days) fits the
existing `maxConsistencyRangeDays` of 366. Agents already get the same
statuses from `GET /agent/protocols/day-statuses` without a `compoundId`, so
no new operation is needed.

### D8. The Progress Overview screen

**Placement.** `_ProgressHomeContent` in
`apps/mobile/lib/features/home/widgets/home_screen.dart` is replaced by
`ProgressOverview`.

`HomeScreen` builds the Progress slot of its `IndexedStack` only while
Progress is the selected destination; otherwise the slot is a
`SizedBox.shrink()`. The providers are `autoDispose`, so nothing is computed
while the user is on Today or Library. The list carries a `PageStorageKey`, so
its scroll position comes back when the user returns. The period choice is a
provider that is not `autoDispose`, so it survives tab switches until the app
restarts.

**Data boundary.** Every card reads through one
`ProgressFeatureRepository`, following the `FocusFeatureRepository` pattern:
an abstract interface, a `RepositoryProgressFeatureRepository` over the real
repositories, a `StubProgressFeatureRepository` with fixed data, and a
`progressFeatureRepositoryProvider`.
*   `PerenniaRoot` gains an optional `progressFeatureRepository` parameter,
    following the `upNextFeatureRepository` pattern in `app.dart`. When the
    parameter is absent and `homeRepository` is given, it installs
    `const StubProgressFeatureRepository()`.
*   `app_shell_test.dart` and the per-card widget tests use the stub, so
    they never open a database.
*   The Progress Overview screen test uses the real repository over an
    in-memory SQLite database.

**Today.** `progressTodayProvider` holds today's local date, read from
`progressClockProvider` (a provider of `DateTime Function()`, defaulting to
`DateTime.now`). It refreshes in two cases:
*   when the app resumes, through an `AppLifecycleListener` it creates and
    disposes with itself;
*   at the next local midnight, through a `Timer` it re-arms after each
    refresh.

A screen left open overnight therefore moves to the new day. No existing
provider tracks the current date: Today's selected day is set once when it is
built. Tests override `progressClockProvider` with a fixed instant.

**Period.** A `SegmentedButton` at the top offers 4 wk, 12 wk and 1 yr,
defaulting to 12 wk. A period of `n` weeks runs from the start of the week
`n - 1` weeks before the current week (by `weekStartDay`) to the end of the
current week. 1 yr is 52 weeks (364 days). Future dates in the period are
shown empty.

**Cards**, in order. Each is a DESIGN.md card (surface color, `md` corners, no
shadow) with an `h2` title, an optional trailing text button to a detail
screen, and a one-line empty state with at most one action when it has
nothing to show. While a card's data is loading it shows its title over a
120 dp empty body. The Protocols card is the exception: it renders nothing
while loading (D7). A card whose content is taller or shorter moves the
cards below it once, when its data arrives.

| # | Card | Title | Trailing button | Opens |
| :- | :--- | :---- | :-------------- | :---- |
| 1 | This week | "This week" | "Routines" | `RoutinePlanListScreen.routeName` |
| 2 | Trained days | "Trained days" | none | none |
| 3 | Time by Focus | "Time by Focus" | "Focuses" | `FocusManagerScreen` |
| 4 | Key exercises | "Key exercises" | none | none |
| 5 | New bests | "New bests · {count}" | none | none |
| 6 | Body | "Body" | "Body Tracker" | `BodyTrackerScreen.routeName` |
| 7 | Protocols | "Protocols" | none | none |
| 8 | More | none | none | the two existing tiles |

1.  **This week.**
    *   Seven equal columns, starting at `weekStartDay`. Each column shows the
        weekday initial, the date number, and the status icon in the
        secondary text color, 24 dp, inside a 48 dp tall cell:

        | Status | Icon |
        | :----- | :--- |
        | Done | `Icons.check_circle` |
        | Partly done | `Icons.timelapse` |
        | Done differently | `Icons.swap_horiz` |
        | Not done | `Icons.radio_button_unchecked` |
        | Pending | `Icons.schedule` |
        | Planned | `Icons.event` |
        | Trained | `Icons.add_circle_outline` |
        | Rest | no icon |
        | No plan | no icon |

        Today's column has a 1 dp outline in the primary text color.
    *   Under the columns, a summary of the counted statuses (D1), each a
        numeral and a label, zero counts omitted, for example "2 done · 1
        done differently · 1 not done · 1 trained".
    *   A legend lists the icon and label of every status present this week,
        including Rest and No plan as text only, so the icon is never the
        only signal.
    *   A line under the legend, by case:

        | Compared Routines | Active rotating Routine | Line |
        | :---------------- | :---------------------- | :--- |
        | one or more | no | "Comparing {names}" |
        | one or more | yes | "Comparing {names}. Weekly Routines only." |
        | none | yes | "Weekly Routines only." |
        | none | no | no line |

        `{names}` are the compared Routines' names, ordered by name
        (case-insensitive), joined with " · ".
    *   The row is not interactive. Its semantics label lists the days, for
        example "This week: Monday done, Tuesday done, Wednesday trained,
        Thursday not done, Friday rest, Saturday done differently, Sunday
        rest."
    *   When every count is zero, the summary reads "Nothing logged yet this
        week".
    *   Empty state, when the user has no compared Routine, no active
        rotating Routine and no Logged Workout this week: "Plan your week
        with a Routine", action "Routines".
2.  **Trained days.**
    *   A count line, "{n} trained days" (plural form from the ARB).
    *   A calendar with one column per week and one row per weekday, starting
        at `weekStartDay`. Cells are square, sized to fit the card's width,
        at most 24 dp, with 2 dp gaps. A Trained Day is a cell filled with
        the primary text color at 70% opacity; any other past or current
        date is a 1 dp outline in the divider color; a future date is blank.
        Weekday initials sit left of the rows, and the first date of every
        fourth week sits above its column as "d MMM" ("3 Aug").
    *   Fill against outline is the signal, so color carries no meaning
        here. The calendar is not interactive. Its semantics label is
        "{n} trained days in the last {weeks} weeks."
    *   Empty state, when the period has no Trained Day: "Logged workouts
        show here", no action.
3.  **Time by Focus.**
    *   One stacked bar per week, drawn with fl_chart's `BarChart`. Segments
        run bottom to top by Focus sort order with "No Focus" last. Each
        segment uses `resolvedFocusColor`, and "No Focus" uses the `other`
        token. Adjacent segments are separated by a 1 dp gap in the card
        surface color.
    *   Gridlines sit at whole hours, labelled "0", "2h", "4h". The step is
        the smallest of 1, 2, 4, 6, 12, 24 and 48 hours that keeps at most
        five gridlines above zero up to the tallest bar. The y axis ends at
        the first gridline at or above the tallest bar. A week has at most
        168 hours, so the 48-hour step always fits.
    *   The legend lists, in sort order with "No Focus" last, every Focus
        (and "No Focus") that has a key in any day of the period. Each entry
        has a color dot and the current week's time, formatted with the
        existing `workoutDurationHoursMinutes` and `workoutDurationMinutes`
        strings ("2h 40m", "35m"); an entry with no time this week shows
        "0m". A Focus id with no Focus row on this device yet (not pulled)
        is labelled "Focus" and drawn in the `other` color.
    *   Semantics label: "Time by Focus, this week: Weights 2 hours 40
        minutes, Endurance 3 hours 10 minutes", built from the new plural
        strings `progressHoursSpoken` and `progressMinutesSpoken`.
    *   Empty state, when the period has no finished Logged Workout:
        "Finished workouts show here", no action.
4.  **Key exercises.**
    *   A two-column grid of tiles, one per active Favorite exercise whose
        profile has a series (D4). Favorites have no order of their own
        (`Exercises.isFavorite` is a flag), so tiles are ordered by name,
        case-insensitive, then by id. At most six are shown. The app has
        no standalone exercise list, so the card has no trailing button.
    *   Each tile shows the exercise name, the measure's label (Data shapes),
        a 40 dp sparkline of the period's points, and "Best {value}" for the
        period. Under it is one comparison line from `periodBest`:

        | Case | Line (higher is better) | Line (lower is better) |
        | :--- | :---------------------- | :--------------------- |
        | better than before | "↑ {difference} on before" | "{difference} faster than before" (pace) or "{difference} shorter than before" (duration) |
        | equal to before | "Same as before" | "Same as before" |
        | worse than before | "Best before {value}" | "Best before {value}" |
        | no earlier point | "First sessions" | "First sessions" |

    *   New Best points are drawn as hollow rings in the primary text color,
        and the tile's semantics label adds "New best on {date}".
    *   A tile with no point in the period shows "No sessions this period"
        in place of the sparkline, "Best" and the comparison line.
    *   Tapping a tile pushes `ExerciseOverviewScreen(exerciseId: …)`.
    *   Empty state: "Mark exercises as favorites to chart them here", no
        action.
    *   When Favorites exist but none has a series: "Your favorites have no
        charted records", no action.
5.  **New bests.**
    *   The five most recent New Bests in the period, each row showing a
        Trophy Gold trophy glyph, "{exercise} · {value}" (prefixed "e1RM"
        for an estimated one-rep max), and its date. The date is the weekday
        ("Sat") when it falls from today minus six days to today, "12 Oct"
        for an earlier date in the current year, and "12 Oct 2025"
        otherwise.
    *   Tapping a row pushes `ExerciseOverviewScreen(exerciseId: …)`.
    *   Empty state: "No new bests in this period", no action.
6.  **Body.**
    *   One row per curated Body Tracker measurement
        (`MeasurementRepository.watchCuratedActive`) with at least one
        Reading in the period, in Body Tracker's order. Each row's Readings
        come from `watchHistoryEntries(measurementId: id)`.
    *   Each row has the name, the latest Trend value with unit, and the
        change over the period (D5), for example "↓ 1.6 kg". Both use one
        decimal, rounded half up, and the Reading's own unit label as Body
        Tracker shows it. Readings are not converted to the unit system
        (D5). A change that rounds to 0.0 reads "No change".
    *   The Trend label carries the hint "Smoothed over about 10 days" as a
        line of secondary text under the card title.
    *   Each row has a 64 dp chart of the period's Readings, drawn as dots in
        the secondary text color under the Trend line in the accent color.
    *   Empty state: "Log a measurement to see its trend", action "Body
        Tracker".
7.  **Protocols.** As D7.
8.  **More.** The two existing `SettingsNavTile`s for Body Tracker and Health
    metrics, unchanged, with new keys `ProgressOverview.bodyTrackerTileKey`
    and `ProgressOverview.healthMetricsTileKey`.

**Charts.**
*   The sparklines in Key exercises and Body use a new `ProgressSparkline`
    built on fl_chart's `LineChart`, the chart library the project has settled
    on and that the Protocols charts already use.
*   Points are placed on the x axis by time, not by index. The y range is the
    minimum and maximum of the drawn values with 10% padding, not a zero
    baseline.
*   The widget takes a list of `(x, y)` points, an optional list of overlay
    `(x, y)` points drawn as a line (the Trend), a set of point indexes drawn
    as hollow rings, and the color of the points and of the line.
*   Nutrition's `_SparklinePainter` is not changed.
*   The Trained days calendar and the This week row are plain widgets, not
    charts.
*   All colors come from `context.colors` and `resolvedFocusColor`.

**Values.** Key exercises and New bests format values with one new
function, `formatProgressValue(ProgressMeasureKind measure, double value,
UnitSystem unitSystem, AppLocalizations l10n)` in
`features/progress/widgets/progress_format.dart`. `ProgressMeasureKind` is
the Dart enum of `measure` values (Data shapes), defined in
`progress_measure.dart`. The input is the engine's normalized value:

| `measure` | Metric | Imperial |
| :-------- | :----- | :------- |
| `estimatedOneRepMax`, `maxLoad` | kg, one decimal, trailing ".0" dropped | lb (× 2.20462), same rounding |
| `maxReps` | whole number, "reps" | same |
| `maxDuration`, `minDuration` | `m:ss` under an hour, else `h:mm:ss` | same |
| `maxDistance` | km, two decimals | mi (÷ 1.609344), two decimals |
| `fastestPace` | `m:ss /km` | `m:ss /mi` (× 1.609344) |

Seconds are rounded half up to whole seconds before formatting. Differences
in the comparison line use the same function, except that a pace or
duration difference under a minute reads "18 s", and one of a minute or more
reads `m:ss` ("1:05").

`unitSystem` is `AppSettings.unitSystem`. Exercise Overview keeps its own
formatting; aligning it is part of the separate Exercise Overview change.

**Change direction.** Arrows show numeric direction only, in the secondary
text color. For lower-is-better measures, the tile says "faster" or "shorter"
in words instead of an arrow. No change is drawn in red, green or gold.

**Numbers.** All numerals use tabular figures.

**Performance.**
*   Each card has its own provider, so a slow card never blocks another.
*   A card still computing shows its loading body (see Cards).
*   `ExerciseAnalyticsRepository.watchNewBests` builds all series inside
    `compute` from `package:flutter/foundation.dart`, the background-isolate
    helper, not the engine's `compute` method. The stub returns data
    directly, so card and app-shell tests settle. The screen test that uses
    the real repository wraps its pumps in `tester.runAsync`.
*   Key exercises computes at most six series on the UI isolate.

**Accessibility.**
*   Each chart is wrapped as `Semantics(container: true, label: …, child:
    ExcludeSemantics(chart))`, the existing pattern.
*   Every tappable row, tile and button is at least 48 dp.
*   With the stub repository showing a populated state for every card, the
    screen passes the text contrast, tap target and labelled tap target
    guidelines that `app_shell_test.dart` already runs on Progress.

### D9. Agent surface

| App view | REST operation | MCP tool | Contract diff |
| :------- | :------------- | :------- | :------------ |
| This week, Trained days, Time by Focus | `GET /agent/progress/training-days`, operationId `listAgentTrainingDays` (new) | `agent_list_training_days` (new) | new path; `AgentTrainingDaysResponse`, `AgentTrainingDay`, `AgentTrainingWeekDay`, `AgentTrainingDayStatus` |
| New bests | `GET /agent/progress/new-bests`, operationId `listAgentNewBests` (new) | `agent_list_new_bests` (new) | new path; `AgentNewBestsResponse`, `AgentNewBest` |
| Key exercises | `GET /agent/analytics/exercises/{exerciseId}`, operationId `getAgentExerciseAnalytics` (changed) | `agent_get_exercise_analytics` (changed) | response adds `progressSeries` |
| Body | `GET /agent/metrics/readings`, operationId `listAgentMetricReadings` (changed) | `agent_list_metric_readings` (changed) | query adds `includeTrend`; each reading may add `trendValue` |
| Protocols | `GET /agent/protocols/day-statuses` (unchanged) | `agent_list_protocol_day_statuses` (unchanged) | none |

**`listAgentTrainingDays`.**
*   Query: `fromLocalDate`, `toLocalDate` (inclusive) and `today`, all
    required. Each uses `LocalDateSchema` from `agent-protocols.ts`, which
    this change exports. A malformed date gets the request validator's own
    400 body, as `GET /agent/protocols/day-statuses` documents for its dates.
*   Range rules: the handler calls the existing exported
    `checkAgentProtocolDaysQuery`. It rejects `fromLocalDate` after
    `toLocalDate`, more than 366 dates, `toLocalDate` after `today`, and a
    `today` more than one day from the server's UTC date. A rejection
    returns 400 `agent_progress_read_invalid_range` with the function's
    message.
*   503 `agent_progress_read_unavailable` when the store is not configured.
    Both codes use the `{code, message}` shape of the nutrition reads.
*   Response: `{days, trainedDayCount, week}`.
    *   `days` is `trainingDays` over the range.
    *   `trainedDayCount` counts `days` with `workoutCount > 0`.
    *   `week` is `{weekStart, days, counts, comparedRoutineIds}` from
        `trainingWeek` and `summarizeTrainingWeek` for the week containing
        `today`, with `weekStart` from the account's synced `weekStartDay`
        setting (`monday` when it has none).
*   The week is always present, whatever the range, so one call answers both
    questions in CUJ 13.

**`listAgentNewBests`.**
*   Query: `fromLocalDate`, `toLocalDate`, with the same rules and errors.
*   Response: `{newBests: AgentNewBest[]}` from `newBestsBetween`, each
    `{exerciseId, exerciseName, measure, workoutId, localDate, startedAt,
    setId, value, unit}`.
*   Values are in the engine's normalized units.

**`progressSeries` on exercise analytics.** The response adds
`progressSeries: ProgressSeries | null` (D4) over the exercise's whole
history. It is null for an archived exercise, a profile with no series, or
when the progress store is not configured. It is read through a new store
method, not through the existing 200-Set page, and is not filtered by the
request's `from` and `to`. The Agent gets the same points the app plots and
can clip them itself. `buildAgentExerciseAnalyticsResponse` gains an
optional `progressSeries` argument that defaults to null, so its other
callers are unchanged.

**`includeTrend` on readings.**
*   Query `includeTrend` is `"true"` or `"false"`, default `"false"`, parsed
    with the `z.enum(["true", "false"])` pattern that `agent-catalog.ts`
    uses. `z.coerce.boolean()` is not used, because it reads `"false"` as
    true.
*   When it is `"true"`, each returned live reading with a scalar value (D5)
    carries `trendValue`, computed with `metricTrend` over all of that
    Metric's live scalar readings, not only the returned page.
*   Archived readings and readings without a scalar value never carry the
    field, and with `"false"` it is absent on every reading.
*   `trendValue` is added to `AgentMetricReadingListItemSchema`, the schema
    the list returns. It is not one of the selectable `fields`: it is
    attached after the `fields` projection whenever `includeTrend` is
    `"true"`.
*   The computation lives in `createDrizzleAgentMetricStore`'s
    `listMetricReadings`, which REST and MCP share.

**Server store.** A new `AgentProgressReadStore` type in
`apps/server/src/agent-progress-reads.ts`, built by
`createDrizzleAgentProgressReadStore(db)` in the same file. It is constructed
in `index.ts` and passed to `createApp` and `createAgentMcpServer` as
`agentProgressReadStore`, like `agentPlanReadStore`. Its methods:

| Method | Returns | Reads |
| :----- | :------ | :---- |
| `readTrainingDays({userId, from, to, today})` | the `listAgentTrainingDays` response | Routines whose payload `cadence_kind` is `weekly` and that are not deleted; their routine entries that are not deleted and have a `slot`; the entries' workout templates that are not deleted; workout sessions whose payload `local_date` is in `[min(from, weekStart), max(to, weekStart + 6)]` and that are not deleted; each session's count of logged sets that are not deleted with payload `is_completed` true; each session's active template link (latest `updated_at`, then highest `id`); the account's `weekStartDay` |
| `readNewBests({userId, from, to})` | the `listAgentNewBests` response | performed sets as defined below, grouped by exercise; their exercises through the catalog |
| `readExerciseProgressSets({userId, exerciseId})` | `ProgressWorkoutSets[]` | the same, for one exercise |

**Loading Sets and exercises.** The store reads `logged_sets` rows that are
not deleted. It joins each to its `workout_sessions` row by the payload's
`workout_id`, drops Sets whose session is deleted, and takes the session's
`started_at` and `local_date`. `isCompleted` is the payload's
`is_completed`, false when missing.

The existing `readLiveLoggedSets` and `mapLoggedSetRow` are not reused,
because they read a missing `is_completed` as true and do not join the
session. Each Set's `exercise_id` is passed through the exported
`resolvePlatformExerciseId` in `agent-catalog.ts`. The distinct ids go to
`AgentCatalogStore.getExercisesByIds`, which the store receives at
construction as `workoutExerciseCatalog` is received in
`agent-read-surface.ts`.

Exercises the catalog does not return, or returns with `active` false, are
skipped. Series are keyed by the resolved id. The name is the catalog
exercise's `name`. The profile comes from a new exported
`agentAnalyticsProfile(exercise: AgentExercise)` in `agent-read-surface.ts`,
extracted from the inline profile in `buildAgentExerciseAnalyticsResponse`,
which then calls it.

**Reused helpers.** The training-days loader reuses `cadenceFromRow`,
`routineEntryFromRow` and `isoWeekday` from `agent-plan-reads.ts`, which this
change exports. `weekStartDay` comes from the settings read store's
`readSettings({userId})` (`createDrizzleAgentSettingsStore`), which the
progress store receives at construction.

The route handlers return 503 when the store is undefined, as the plan-read
routes do.

**Agent skill.** Each new MCP tool is listed in `AGENT_MCP_TOOL_NAMES` and
`AGENT_SKILL_COMMAND_NAMES`, and gets a `prn-agent` command
(`progress-training-days` and `progress-new-bests`). `PortableOwlAgentClient`
in `agent-skills/perennia/scripts/prn-code.mjs` gains a method per new
operationId (`listAgentTrainingDays`, `listAgentNewBests`), as
`apps/server/test/agent-skill.test.mjs` requires. Both operations appear in
the generated `agent-skills/perennia/references/api-operations.md`.

### Data shapes

Dates are `YYYY-MM-DD` strings in vectors and the API (`TrainingDayDate` in
Dart). Instants are ISO-8601 UTC strings in vectors and the API (`DateTime`
in Dart). Field names are the same in Dart, TypeScript, vectors and the API.
A field marked `?` is always present, with `null` when it has no value.

The core types live in the core files: `training_progress.dart`,
`progress_measure.dart` and `metric_trend.dart`, and their TypeScript
mirrors.

| Type | Fields |
| :--- | :----- |
| `WeeklyPlan` | `routineId`, `entries: WeeklyPlanEntry[]` |
| `WeeklyPlanEntry` | `workoutTemplateId`, `weekday` (1-7) |
| `ProgressWorkout` | `workoutId`, `localDate`, `startedAt`, `endedAt?`, `focusId?`, `linkedTemplateId?`, `performedSetCount` |
| `TrainingWeek` | `weekStart`, `days: TrainingWeekDay[]` (7), `comparedRoutineIds: string[]` |
| `TrainingWeekDay` | `localDate`, `status` (D1's nine wire values), `plannedCount`, `matchedCount`, `workoutCount` |
| `TrainingWeekCounts` | `done`, `partlyDone`, `doneDifferently`, `notDone`, `trained` |
| `TrainingDay` | `localDate`, `workoutCount`, `secondsByFocus: {[focusIdOrNone]: int}` |
| `WeeklyFocusSeconds` (Dart only) | `weekStart`, `secondsByFocus` |
| `ProgressSet` | `id`, `position`, `isCompleted`, `values` (the engine's logged-values shape) |
| `ProgressWorkoutSets` | `workoutId`, `localDate`, `startedAt`, `sets: ProgressSet[]` |
| `ProgressPoint` | `workoutId`, `localDate`, `startedAt`, `setId`, `value`, `unit`, `isNewBest` |
| `ProgressSeries` | `exerciseId`, `measure`, `betterIs` (`higher` or `lower`), `points: ProgressPoint[]` |
| `NewBest` | `exerciseId`, `measure`, and the `ProgressPoint` fields except `isNewBest` |
| `PeriodBest` (Dart only) | `best: ProgressPoint?`, `bestBefore: double?` |
| `TrendInput` | `id`, `at`, `value?` |
| `TrendPoint` | `id`, `at`, `value`, `trend` |

`measure` is one of `estimatedOneRepMax`, `maxLoad`, `maxReps`,
`maxDuration`, `minDuration`, `maxDistance`, `fastestPace`; the Dart enum is
`ProgressMeasureKind`. Its display labels are "e1RM", "heaviest", "most
reps", "longest", "shortest", "farthest" and "fastest pace". `unit` is the
engine's `TrainingUnit` name (D4).

`TrendInput` is not the metrics feature's `MetricReadingPoint`, because the
core must not depend on feature record types.

Repository-side types, which add display names:

| Type | File | Fields |
| :--- | :--- | :----- |
| `WeeklyPlanFacts` | `routine_up_next_repository.dart` | `routineId`, `routineName`, `entries: WeeklyPlanEntry[]`; `toWeeklyPlan()` drops the name |
| `CompoundConsistencySummary` | `protocol_plan_repository.dart` | `compoundId`, `compoundName`, `logged`, `partlyLogged`, `notLogged`, `paused` |
| `ProgressBodyRow` | `progress_controller.dart` | `measurementId`, `name`, `unitLabel`, `readings: TrendPoint[]` (the period's), `latestTrend: double`, `change: double?` |

The Workout loader returns `ProgressWorkout` directly; there is no separate
facts type.

**Vector cases.** Each case is `{"name", "function", "input", "expected"}`,
the shape `m36-protocol-plan.json` uses:
*   `function` is the snake_case core function name: `training_week`,
    `summarize_training_week`, `training_days`, `progress_series`,
    `new_bests_between` or `metric_trend`.
*   `input` holds the function's named arguments.
*   `expected` holds its full result, or `{"error": "argument"}` for a
    rejected input.

Each file's header is `{name, domain, schemaVersion: 1, schema, cases}`, as
in `m36-protocol-plan.json`. `m37-metric-trend.json` adds a top-level
`tolerance: 1e-9`. Its runners compare the `trend` fields within it and
everything else exactly. `packages/golden-vectors/vectors/README.md` gains a
section for each new file.

An example taken from CUJ 2, reduced to the Thursday plan:

```json
{"name": "cuj2-today-pending",
 "function": "training_week",
 "input": {"plans": [{"routineId": "r1",
   "entries": [{"workoutTemplateId": "t-upper", "weekday": 4}]}],
   "workouts": [{"workoutId": "w1", "localDate": "2026-10-29",
     "startedAt": "2026-10-29T06:00:00.000Z", "endedAt": "2026-10-29T06:45:00.000Z",
     "focusId": "f-e", "linkedTemplateId": null, "performedSetCount": 1}],
   "weekStart": "2026-10-26", "today": "2026-10-29"},
 "expected": {"weekStart": "2026-10-26", "comparedRoutineIds": ["r1"], "days": [
   {"localDate": "2026-10-26", "status": "rest", "plannedCount": 0, "matchedCount": 0, "workoutCount": 0},
   {"localDate": "2026-10-27", "status": "rest", "plannedCount": 0, "matchedCount": 0, "workoutCount": 0},
   {"localDate": "2026-10-28", "status": "rest", "plannedCount": 0, "matchedCount": 0, "workoutCount": 0},
   {"localDate": "2026-10-29", "status": "pending", "plannedCount": 1, "matchedCount": 0, "workoutCount": 1},
   {"localDate": "2026-10-30", "status": "rest", "plannedCount": 0, "matchedCount": 0, "workoutCount": 0},
   {"localDate": "2026-10-31", "status": "rest", "plannedCount": 0, "matchedCount": 0, "workoutCount": 0},
   {"localDate": "2026-11-01", "status": "rest", "plannedCount": 0, "matchedCount": 0, "workoutCount": 0}]}}
```

### Validation and analytics

*   **Validation.** One new hard reject, `focus_color_hex`, app only (D6).
    The shared plan validation module and `m33-plan-validation.json` are
    unchanged.
*   **Analytics.** Three new derived computations, each with Dart and
    TypeScript implementations agreeing on `m37-training-progress`,
    `m37-progress-measure` and `m37-metric-trend`:
    *   D1 and D2: Training Day Status and Trained Days;
    *   D4: Progress Measure;
    *   D5: Trend.

    The existing `m4-analytics-pr-e1rm-volume` vectors are unchanged, because
    D4 calls the engine instead of changing it.

### Invariants this touches

| [Invariant](../../AGENTS.md#non-negotiable-invariants) | How it is preserved |
| :-------------------- | :------------------ |
| A Workout is a session, not a day-bucket | Statuses and Trained Days are derived per date from Workouts; nothing is stored per day. |
| Sets are self-describing | The Progress Measure reads stored values and units through the existing engine. Nothing writes to Sets. |
| Derived analytics are computed, never stored or synced | Statuses, Trained Days, time, Progress Measures, New Bests and Trends are computed on read. Focus color is authored, written only by the user's edits. |
| User-facing delete is archive | Archived Routines and archived templates plan nothing; archived Focuses keep their time and color; archived exercises leave Key exercises and New bests, but their Workouts still count toward Training Day Statuses, Trained Days and time. |
| Restore and import are merge-only | Old archives import with a null Focus color. No delete path is added. |
| Local writes never block on the network | Recolor is local first. |
| Sync is silent LWW with recoverable losers | `color_hex` travels in the Focus payload and wins or loses with it. Server carry-forward and undo equality (D6) keep an older device from erasing it; the Activity Log keeps the loser. |
| One shared two-tier validation module | Unchanged. `focus_color_hex` is app-only, like Category color, because no Agent writes it. |
| No behavioral analytics | Nothing on Progress is reported anywhere. |

## Alternatives Considered

### Alternative A: Compare past weeks with the plan

*   **Pros:** Answers "did I follow my plan" for months, not one week.
*   **Cons:** Routines keep no history of their plan. Comparing an old date
    with today's plan marks weeks "Not done" against a plan the user did not
    have then.

    The reviewed draft tried to fix this with one authored Plan Date per
    Routine. Making that date correct needed:
    *   about ten write paths in two languages to stamp it;
    *   a server carry-forward key and an undo equality rule;
    *   Agent write rules and a validation rule;
    *   a fallback for Routines untouched since the upgrade, on which the
        app and the server could disagree by a day;
    *   a per-field merge rule to stop it moving backward under
        last-writer-wins, which bends the sync invariant.

    Even then, any plan edit cut the compared history of every Routine.
    Versioning Routine plans the way Protocol Schedules are versioned would
    be correct, but it adds a table, a sync entity and history rules for
    every Routine edit.
*   **Reason for rejection:** The current week needs none of this, and
    Trained Days answer "am I showing up" for longer periods. Plan history,
    if users ask for it, gets its own spec built on plan versions.

### Alternative B: One "progress overview" Agent operation

*   **Pros:** One call for everything on the screen.
*   **Cons:** Couples unrelated views and cores into one response, and the
    Agent pays for every card on each call.
*   **Reason for rejection:** Each view gets the read that matches its core,
    and three of them reuse existing operations.

### Alternative C: A consistency percentage or streak

*   **Pros:** Quick to read.
*   **Cons:** A score is a judgment and a streak is a reward. The product
    rules and the Protocols spec reject both.
*   **Reason for rejection:** Statuses and counts describe without grading.

### Alternative D: Match Done by Routine and slot, as Up next does

*   **Pros:** Uses exactly what the Template Link records, and agrees with Up
    next's tick.
*   **Cons:** A planned workout started from the saved-workouts list would
    never be Done.
*   **Reason for rejection:** Progress reports what the user did, not which
    button started it. D1 records the difference from Up next.

### Alternative E: Count any Workout with a Set, completed or not

*   **Pros:** No new rule; matches Exercise Overview today.
*   **Cons:** Starting a planned workout from Up next places incomplete Sets.
    An abandoned start would read Done, add time and can create false New
    Bests from prescribed values.
*   **Reason for rejection:** The codebase already treats only completed Sets
    as performed (D0). Progress follows that rule.

### Alternative F: Focus colors from sort order, or seeded into rows

*   **Pros:** Sort order needs no hash; seeding makes starters explicit.
*   **Cons:** Sort order recolors history on reorder. Seeding touches the
    seed pipeline and leaves existing installs with nulls anyway.
*   **Reason for rejection:** A default from the Focus id stays the same on
    every device and needs no seed change.

### Alternative G: Color the Trained days calendar by Focus

*   **Pros:** Shows which discipline each day was.
*   **Cons:** In cells of 4 to 24 dp with no room for labels, the hue would
    be the only signal for the Focus, which DESIGN.md and AGENTS.md forbid.
    Days with two Focuses need a rule for which wins.
*   **Reason for rejection:** Time by Focus, one card below, shows the Focus
    balance with a legend.

### Alternative H: A pinned key-exercise list

*   **Pros:** Independent from Favorites, which also order pickers.
*   **Cons:** A new synced setting and an editor.
*   **Reason for rejection:** Favorites already mean "the exercises I care
    about".

### Alternative I: A simple moving average for the Trend

*   **Pros:** Easy to explain.
*   **Cons:** Needs a window, lags more, and weights readings wrongly when the
    gaps between them vary.
*   **Reason for rejection:** The time-weighted average handles gaps and needs
    no window.

### Alternative J: Show the change from the period's first to last point

*   **Pros:** Simple.
*   **Cons:** A light final session reads as a decline for someone who is
    improving.
*   **Reason for rejection:** The period's best against the best before it
    shows progress without that distortion.

### Alternative K: List the engine's standing records set in the period

*   **Pros:** The engine already returns records with `achievedAt`, so New
    bests would need no new core.
*   **Cons:** Standing records are only the current ones. A best set in week
    one and beaten in week three would vanish from the list. A rep-max
    exercise would list rep-max records, not estimated one-rep max.
*   **Reason for rejection:** New bests reports every improvement in the
    period, which needs the per-Workout series.

### Alternative L: Hand-written chart painters

*   **Pros:** Full control, and Nutrition already has a painter.
*   **Cons:** AGENTS.md settles fl_chart for charts, and the Nutrition painter
    spaces points by index from a zero baseline, which cannot draw a weight
    Trend.
*   **Reason for rejection:** fl_chart already draws the Protocols charts, so
    Progress uses it as well.

## Risks and Mitigations

*   **Auto-finished Workouts add time.** The existing auto-finish ends a
    forgotten Workout one hour after its last activity, so it can add up to
    an hour. Accepted: capping at the last Set's time would cut real
    endurance sessions whose single Set is logged at the end, and Set times
    are optional.
*   **Exercise Overview disagrees with Progress on incomplete Sets.**
    Exercise Overview counts incomplete Sets in its records; Progress does
    not (D0). A placeholder with a prescribed load can show as a record there
    and not here. Accepted for this spec. Changing Exercise Overview's input
    to Performed Sets changes existing records and the `m4` vectors, so it is
    its own change.
*   **A Platform exercise hidden by a same-named user exercise.** The
    server's catalog hides a Platform exercise when the user has an active
    exercise with the same name, so its Sets drop out of the Agent's New
    Bests while the app still counts them. This is the catalog's existing
    rule for every Agent read, and the case is rare. Accepted.
*   **Up next and This week can differ on a day** (D1). Accepted and
    explained in D1; each answers a different question.
*   **Plan edits mid-week** re-judge that week's earlier days (D1). Accepted.
*   **An unused weekly Routine keeps days Not done.** This week names the
    compared Routines, so the user can see and archive it.
*   **Default Focus colors can collide.** Two user Focuses can hash to the
    same color. Segment gaps and the full legend keep the bars readable, and
    the user can recolor either Focus.
*   **Agent undo of an older device's Focus edit.** While an account mixes
    app versions, the server carries `color_hex` forward into a Focus that an
    older device pushed (D6), so the stored payload no longer equals that
    entry's after-image. The Agent's undo compares the two exactly
    (`isDeepStrictEqual` in `agent-activity.ts`) and returns
    `skipped_stale` for that entry. The edit stays in place and nothing is
    lost; the user can still change the Focus directly. Accepted: the window
    closes once every device updates, and treating a missing key as null in
    the Agent's undo is left for a change that covers every carried-forward
    key.
*   **Large histories.** New bests builds a series for every exercise over
    its whole history. It runs only while Progress is visible (D8), in a
    background isolate, and its card shows a fixed-height empty body until
    done. The speed requirement below is measured.
*   **The lock and the Agent.** The Protocols lock is a device display
    control. The Agent's existing Protocols reads are not affected by it, as
    today. The card checks the lock on every build, so content from before
    the app went to the background is not shown after it re-locks.
*   **Two kinds of gold.** The trophy on a set row marks a rep-max record; a
    New bests row for a rep-max exercise says "e1RM" (D4).

## Non-Functional Requirements

*   **Speed.** These are budgets in the existing
    `apps/mobile/test/performance/performance_budgets_test.dart`, which CI
    already runs. Each budget is a constant in
    `performance_budget_thresholds.dart`, and each row is added to
    `apps/mobile/test/performance/README.md`. The fixture is
    `buildProgressHistoryFixture()`, described in the Detailed
    Implementation Plan: five years of history, with 1 500 Workouts, 60 000
    Sets over 40 exercises, and 2 000 Readings.

    | Budget | Work | Limit |
    | :----- | :--- | :---- |
    | `progressTrainingBudget` | `trainingWeek` plus `trainingDays` over 366 days | < 50 ms |
    | `progressNewBestsBudget` | `progressSeries` for every exercise plus `newBestsBetween` | < 1 000 ms |
    | `progressTrendBudget` | `metricTrend` over 2 000 Readings | < 20 ms |

    These are host timings, like the existing budgets. Each card provider
    also wraps its work in a `developer.Timeline` span named
    `progress.{card}`, so a profile build can be inspected in DevTools.
*   **Offline.** Every card works in Local-only Mode.
*   **Accessibility.** WCAG AA contrast in both themes; tap targets at least
    48 dp; every chart has a semantics label; no status or Focus is shown by
    color alone.
*   **Localization.** Every string is in `app_en.arb`. Every new widget file
    is listed in `l10n_externalization_test.dart`.
*   **Privacy.** No Compound name renders while Protocols are locked or the
    lock state is unavailable, and the locked card is the same whether or
    not Protocols exist.

## Detailed Implementation Plan

The work lands in four implementation pull requests, each against `main`
after the previous one merges. Each pull request ships an app feature
together with the Agent read that returns the same numbers.

*   **PR 1:** Focus color.
*   **PR 2:** Progress Overview with This week, Trained days, Time by Focus,
    Protocols and More, plus `listAgentTrainingDays`.
*   **PR 3:** Key exercises and New bests, plus their Agent reads.
*   **PR 4:** Body, plus `includeTrend`.

Until PR 2 merges, the Progress root keeps its current two links. Generated
files are regenerated, never edited, in the pull request that changes their
source:
*   `app_database.g.dart` with `dart run build_runner build`;
*   `app_localizations*.dart` with `flutter gen-l10n`;
*   `packages/contract/openapi.json`, the generated clients and
    `agent-skills/perennia/references/api-operations.md` with `pnpm
    generate` in `packages/contract`.

### PR 1: Focus color

1.  **`apps/mobile/lib/data/local/app_database.dart`** (modify). `Focuses`
    gains `TextColumn get colorHex => text().nullable()();`. Set
    `schemaVersion` to 63, with a `from < 63` block that adds the column
    behind the existing `_columnExists` guard. No backfill.
2.  **`apps/mobile/drift_schemas/app_database/drift_schema_v63.json`,
    `apps/mobile/test/generated_migrations/app_database/schema.dart` and
    `schema_v63.dart`** (generate) by the steps in `docs/releasing.md`. Do
    not edit the v62 snapshot.
3.  **`apps/mobile/test/data/schema_snapshot_migration_test.dart`** (modify).
    Seed a Focus at v62 and check that it survives at v63 with a null
    `colorHex`.
4.  **`apps/mobile/lib/data/repositories/focus_repository.dart`** (modify).
    *   `_focusFromRow`, `_focusImage`, `_focusCompanionFromImage` and
        `_focusSyncCompanionFromImage` carry `color_hex`. On decode, a
        missing key leaves the column unchanged (`Value.absent()`) and an
        explicit null clears it, as `_imageFocusId` does.
    *   Add `Future<void> recolor(String id, {required String colorHex,
        String actor = 'app', String? batchId})`. It calls the existing
        `_normalizeColorHex` and `_requireRow`. When the normalized color
        equals the stored one, it returns without writing. Otherwise it
        writes `colorHex` and `updatedAt` and appends the Activity Log entry
        in the same transaction, as `rename` does.
5.  **`apps/mobile/lib/data/repositories/training_repositories.dart`**
    (modify). In `_activityImagesEqualForEntity`, for
    `AppDatabase.focusesTable`, compare copies of both images in which a
    missing `color_hex` is set to null.
6.  **`apps/mobile/lib/domain/training/training_records.dart`** (modify).
    `FocusRecord` gains `final String? colorHex` and a matching optional
    constructor parameter. It has no `copyWith` or equality today, and none
    is added.
7.  **`apps/mobile/lib/domain/training/focus_color.dart`** (create).
    *   The five starter Focus id constants from D6's table:
        `starterFocusWeightsId`, `starterFocusEnduranceId`,
        `starterFocusFunctionalId`, `starterFocusCalisthenicsId` and
        `starterFocusMobilityId`.
    *   `int fnv1a32(String value)`.
    *   `String focusDefaultColorToken(String focusId)` (D6).
8.  **`apps/mobile/lib/features/focus/widgets/focus_visuals.dart`** (modify).
    *   Key the `_starterFocusIcons` map with the item 7 constants.
    *   Add `Color resolvedFocusColor(FocusRecord focus, AppColors colors)`
        (D6), using `colorFromHex` and `AppColors.categoryColor`.
9.  **`apps/mobile/lib/theme/app_colors.dart`** (modify) and
    **`apps/mobile/lib/features/workout_templates/widgets/workout_template_editor_screen.dart`**
    (modify).
    *   Move `_colorToHex` from the editor into `app_colors.dart` as the
        public `String colorToHex(Color color)`, next to `colorFromHex`.
    *   The editor calls the moved function.
10. **`apps/mobile/lib/features/focus/repositories/focus_feature_repository.dart`**
    (modify). Add `Future<void> recolor(String id, String colorHex)` to the
    interface, positional like `rename`. The real implementation calls item
    4; the stub's `recolor` does nothing, like its other writes.
11. **`apps/mobile/lib/widgets/color_swatch_row.dart`** (create).
    *   `class ColorSwatchOption {const ColorSwatchOption({required this.hex,
        required this.label, this.key}); final String hex; final String
        label; final Key? key;}`.
    *   `ColorSwatchRow({required List<ColorSwatchOption> options, required
        String? selectedHex, required ValueChanged<String> onSelected})`.
    *   It renders a `Wrap` of the same `IconButton`s the Category manager
        builds today, at least 48 dp each:
        *   `tooltip` is `option.label`;
        *   `key` is `option.key`;
        *   `onPressed` is null for the selected option, so that one is
            disabled, and otherwise calls `onSelected(option.hex)`.
12. **`apps/mobile/lib/features/catalog/widgets/category_manager_screen.dart`**
    (modify). Replace its swatch row with `ColorSwatchRow`. It passes its
    existing palette, each option labelled `'Use $colorHex'` as today, and
    as each option's `key` the key its swatch has today.
13. **`apps/mobile/lib/features/focus/widgets/focus_manager_screen.dart`**
    (modify).
    *   `_FocusMenu` gains a **Color** item, keyed
        `FocusManagerScreen.colorMenuKey(focusId)` (`Key('focus-manager.color.$focusId')`).
    *   The item opens the D6 dialog. It shows `ColorSwatchRow` over the
        seven tokens, keyed `Key('focus-color.$token')`, and a Cancel button
        keyed `Key('focus-color.cancel')`.
    *   Choosing a swatch calls `recolor` on `focusFeatureRepositoryProvider`.
    *   Each Focus row shows a 12 dp dot of its `resolvedFocusColor` beside
        the name.
14. **`apps/server/src/sync.ts`** (modify).
    *   Add `[FOCUSES_SYNC_ENTITY]: ["color_hex"]` to
        `SYNC_CARRY_FORWARD_PAYLOAD_KEYS`.
    *   Add `payload` to the columns that
        `pushAccountKeyedSyncRowsInTransaction`'s shared `readExisting`
        selects (D6).
15. **`apps/mobile/lib/l10n/app_en.arb`** (modify). Add:
    *   `focusColorMenu` ("Color");
    *   `focusColorDialogTitle` ("Color for {name}");
    *   `focusColorBack`, `focusColorCardio`, `focusColorCore`,
        `focusColorShoulders`, `focusColorArms`, `focusColorLegs` and
        `focusColorChest`.
16. **`CONTEXT.md`** (modify). The changed Focus definition.
17. **Tests.**
    *   `apps/mobile/test/data/focus_repository_test.dart` (modify):
        *   recolor, and its Activity Log entry;
        *   recolor to the stored color writes nothing;
        *   an invalid hex rejected;
        *   recolor of an archived Focus;
        *   a sync image without `color_hex` leaves the color;
        *   a sync image with explicit null clears it;
        *   undo of an entry whose images lack `color_hex` succeeds.
    *   `apps/mobile/test/data/focus_recolor_reopen_test.dart` (create).
        Follow `apps/mobile/test/features/protocols/protocol_plan_reopen_test.dart`:
        *   a temporary-file database through `NativeDatabase` with an
            interceptor that throws at a kill point before the update and,
            in a second case, before the commit;
        *   reopen it with `AppDatabase.openFile`;
        *   assert that the Focus row's `colorHex` and its Activity Log
            entry are both present or both absent.
    *   `apps/mobile/test/domain/focus_color_test.dart` (create):
        *   each starter's token;
        *   `fnv1a32` of three fixed strings against known values;
        *   a fixed user id's token;
        *   the same token after a reorder.
    *   `apps/mobile/test/features/focus/focus_visuals_test.dart` (modify):
        `resolvedFocusColor` with a stored color, with none, and with a
        malformed stored value (falls back to the default).
    *   `apps/mobile/test/features/focus/focus_manager_screen_test.dart`
        (create): CUJ 8 against in-memory SQLite through the real
        repository; the dialog's seven labels and its selected swatch; 48 dp
        targets.
    *   `apps/mobile/test/features/catalog/category_manager_screen_test.dart`
        (modify): the existing swatch tests pass unchanged, and a new test
        asserts the tooltip labels.
    *   `apps/mobile/test/data/portable_archive_repository_test.dart`
        (modify): an archive Focus without `colorHex` imports with null.
    *   `apps/server/test/focus-sync.test.mjs` (modify): a Focus pushed with
        `color_hex`, then pushed again without the key, keeps `color_hex`.

### PR 2: Progress Overview, training cores and `listAgentTrainingDays`

18. **`packages/golden-vectors/vectors/m37-training-progress.json` and
    `.schema.json`** (create). `domain: "training-progress"`, header and
    case shape as in Data shapes. Required cases:
    *   `training_week`:
        *   CUJs 1, 2, 3 and 5 with the CUJs' Routine and dates, and CUJ 4
            with a Wednesday `today`;
        *   a past day with two planned entries and one matched
            (`partly_done`);
        *   two Routines planning the same template on one day;
        *   one Routine planning a template twice on one day;
        *   a Workout with no link on a planned day (`done_differently`);
        *   an Open Workout linked to the planned template on a planned day
            (`done`);
        *   a Workout with `performedSetCount` 0, linked to the planned
            template on a past planned day (`not_done`);
        *   today with one of two planned entries matched (`pending`);
        *   today with every planned entry matched (`done`);
        *   no plans (`trained` and `no_plan` only);
        *   a plan with no entries (ignored);
        *   a Workout dated outside the week (ignored);
        *   a Sunday `weekStart`;
        *   `today` outside the week (`{"error": "argument"}`).
    *   `summarize_training_week`: CUJ 1's days.
    *   `training_days`:
        *   a Workout without a Focus (`"none"` key);
        *   two Focuses on one date;
        *   an Open Workout (counted, no key);
        *   a Workout ending before it started (0 seconds, key present);
        *   a Workout with `performedSetCount` 0 (ignored);
        *   a Workout dated outside the range (ignored);
        *   a 366-date range;
        *   a 367-date range (`{"error": "argument"}`);
        *   `from` after `to` (`{"error": "argument"}`).
19. **`apps/mobile/lib/domain/training/training_progress.dart`** (create).
    *   `TrainingWeek trainingWeek({required Iterable<WeeklyPlan> plans,
        required Iterable<ProgressWorkout> workouts, required TrainingDayDate
        weekStart, required TrainingDayDate today})`.
    *   `TrainingWeekCounts summarizeTrainingWeek(Iterable<TrainingWeekDay>
        days)`.
    *   `List<TrainingDay> trainingDays({required Iterable<ProgressWorkout>
        workouts, required TrainingDayDate from, required TrainingDayDate
        to})`.
    *   `List<WeeklyFocusSeconds> weeklyFocusSeconds(Iterable<TrainingDay>
        days, TrainingDayDate firstWeekStart)`.
    *   `enum TrainingDayStatus` with D1's nine values, each carrying its
        wire value as `final String wireName`, like `DayStatusKind`.
    *   Plain data classes for the Data shapes types, with no Flutter
        imports.
20. **`apps/server/src/analytics/training-progress.ts`** (create). The
    TypeScript mirror of item 19, without `weeklyFocusSeconds`.
21. **Runners.**
    *   `apps/mobile/test/domain/training_progress_golden_test.dart`
        (create). Locate the vectors directory the way
        `barcode_candidates_golden_test.dart` does, so the file contains the
        literal `golden-vectors` that `tools/ci-local.mjs` looks for. Check
        `schemaVersion`, and dispatch each case on `function`.
    *   Register `training-progress` in
        `apps/mobile/test/domain/golden_vector_ownership_test.dart`. Add unit
        tests for `weeklyFocusSeconds` with a Monday and a Sunday first week.
    *   `apps/server/test/training-progress.golden.test.mjs` (create), with
        the same dispatch. Add it to `test:golden-vectors` in
        `apps/server/package.json`. Add `training-progress` to
        `DOMAINS_OWNED_ELSEWHERE` in
        `apps/server/test/agent-validation.golden.test.mjs`.
    *   Add the server runner to the `golden_vectors` path filter in
        `.github/workflows/ci.yml` and to the matching list in
        `tools/ci-local.mjs`, in the same commit.
    *   Add a section for the file to
        `packages/golden-vectors/vectors/README.md`.
22. **`apps/mobile/lib/data/repositories/routine_up_next_repository.dart`**
    (modify).
    *   Add `class WeeklyPlanFacts` (Data shapes).
    *   Add `Stream<List<WeeklyPlanFacts>> watchWeeklyPlans()`. It reuses
        the select of `_watchCadencedRoutines`, which drops archived
        Routines, archived entries and archived templates. Its inner joins
        also leave out a Routine with no live entries.
    *   `watchWeeklyPlans` keeps Routines whose `cadenceKind` is `weekly`,
        drops entries whose `slot` is null, and maps each `slot` to
        `weekday`.
    *   Add `Stream<bool> watchHasRotatingRoutine()`, true when an active
        Routine has `cadenceKind` `rotating`.
    *   `TrainingRepositories.routineUpNext` already exposes this
        repository.
23. **`apps/mobile/lib/data/repositories/training_repositories.dart`**
    (modify). On `WorkoutSessionRepository`, add
    `Stream<List<ProgressWorkout>> watchProgressWorkoutsBetween(
    TrainingDayDate from, TrainingDayDate to)`. It reads Workouts with
    `deletedAt` null and `localDate` in the range. For each Workout it
    returns:
    *   its count of Sets with `deletedAt` null and `isCompleted` true;
    *   its `focusId`;
    *   the `workoutTemplateId` of its Template Link, choosing among links
        with `deletedAt` null the one with the latest `updatedAt`, then the
        highest `id`.
24. **`apps/mobile/lib/data/repositories/protocol_plan_repository.dart`**
    (modify). Add `class CompoundConsistencySummary` (Data shapes) and
    `Stream<List<CompoundConsistencySummary>>
    watchConsistencySummary(ProtocolDayDate from, ProtocolDayDate to,
    {required ProtocolDayDate today})` (D7).
25. **`apps/mobile/lib/features/progress/repositories/progress_feature_repository.dart`**
    (create).
    *   `abstract interface class ProgressFeatureRepository` with:
        *   `Stream<List<WeeklyPlanFacts>> watchWeeklyPlans()`;
        *   `Stream<bool> watchHasRotatingRoutine()`;
        *   `Stream<List<ProgressWorkout>>
            watchProgressWorkoutsBetween(TrainingDayDate from,
            TrainingDayDate to)`;
        *   `Stream<Map<String, FocusRecord>> watchFocusesById()`;
        *   `Stream<List<CompoundConsistencySummary>>
            watchConsistencySummary(TrainingDayDate from, TrainingDayDate to,
            {required TrainingDayDate today})`.
    *   `RepositoryProgressFeatureRepository`, built from
        `TrainingRepositories` and the `FocusFeatureRepository`.
        *   `watchFocusesById` delegates to
            `FocusFeatureRepository.watchAllById`, so it waits for the seed
            as that does.
        *   `watchConsistencySummary` converts the dates (D7) and delegates
            to item 24.
        *   The other methods delegate to items 22-23.
    *   `StubProgressFeatureRepository`, with a const constructor taking
        each stream's data, defaulting to empty.
    *   `progressFeatureRepositoryProvider`, built from
        `trainingRepositoriesProvider` and `focusFeatureRepositoryProvider`.

    PR 3 and PR 4 extend this interface.
26. **`apps/mobile/lib/app.dart`** (modify). `PerenniaRoot` gains `final
    ProgressFeatureRepository? progressFeatureRepository`. It overrides
    `progressFeatureRepositoryProvider` when given, and otherwise installs
    `const StubProgressFeatureRepository()` when `homeRepository` is given,
    exactly as the `upNextFeatureRepository` block does.
27. **`apps/mobile/lib/features/progress/controllers/progress_controller.dart`**
    (create).
    *   `progressClockProvider` and `progressTodayProvider` (D8).
    *   `progressPeriodProvider`: a Notifier of `ProgressPeriod {weeks4,
        weeks12, year}`, defaulting to `weeks12`, not `autoDispose`.
    *   `progressRangeProvider`: `from`, `to`, `today`, `weekStart` and
        `firstWeekStart`, from the period, today and
        `AppSettings.weekStartFor`.
    *   One `autoDispose` `StreamProvider` per repository stream (the
        codebase has no stream-combining package). Each card provider is an
        `autoDispose` `Provider<AsyncValue<T>>` that `ref.watch`es the
        stream providers it needs, returns loading until all have data, and
        then runs its core inside a `developer.Timeline` span named
        `progress.{card}`:
        *   `progressThisWeekProvider`: `trainingWeek`,
            `summarizeTrainingWeek`, the compared Routines' names and the
            rotating flag;
        *   `progressTrainedDaysProvider`: `trainingDays` and the Trained
            Day count;
        *   `progressFocusTimeProvider`: `weeklyFocusSeconds` and the Focus
            records;
        *   `progressProtocolsProvider`: the lock state and the summaries.
28. **`apps/mobile/lib/features/progress/widgets/progress_overview.dart`**
    (create).
    *   The period control and the cards in D8's order, in a `ListView`
        with a `PageStorageKey` and `AppDimens.base` padding, inside the
        `SafeArea` that `_ProgressHomeContent` uses today.
    *   It defines `ProgressOverview.bodyTrackerTileKey` and
        `ProgressOverview.healthMetricsTileKey`.
    *   Its More section holds the two `SettingsNavTile`s that
        `_ProgressHomeContent` builds today.
29. **`apps/mobile/lib/features/progress/widgets/`** (create).
    *   `progress_card.dart`: the shared card frame, with the title, an
        optional trailing button, the empty state and the 120 dp loading
        body.
    *   `this_week_card.dart`.
    *   `trained_days_card.dart`.
    *   `focus_time_card.dart`, using fl_chart's `BarChart`.
    *   `protocols_progress_card.dart`, with rows that push the gated
        Consistency view (D7).
30. **`apps/mobile/lib/features/progress/widgets/progress_format.dart`**
    (create). `String formatFocusDuration(int seconds, AppLocalizations
    l10n)` over the existing `workoutDurationHoursMinutes` and
    `workoutDurationMinutes` strings, after rounding to whole minutes half
    up. PR 3 adds `formatProgressValue` to this file.
31. **`apps/mobile/lib/features/home/widgets/home_screen.dart`** (modify).
    Replace `_ProgressHomeContent` with `const ProgressOverview()`, and build
    the Progress slot only while Progress is selected (D8).
32. **`apps/mobile/lib/l10n/app_en.arb`** (modify).
    *   `progress*` keys for every string in D7 and D8 used by this pull
        request's cards.
    *   The nine status labels `progressStatusDone` to
        `progressStatusNoPlan`.
    *   `progressHoursSpoken` and `progressMinutesSpoken`.
    *   Plural forms for the counts.
33. **`apps/mobile/test/l10n/l10n_externalization_test.dart`** (modify).
    Add each widget file created in items 28-30 to its file list. PR 3 and
    PR 4 add their card files the same way.
34. **Agent server.**
    *   `apps/server/src/agent-progress-reads.ts` (create):
        *   the Zod schemas, with `AgentTrainingDayStatus` as the nine wire
            values;
        *   the `createRoute` definition for `listAgentTrainingDays`;
        *   the `AgentProgressReadStore` type with `readTrainingDays`;
        *   `createDrizzleAgentProgressReadStore({db, settingsStore,
            catalogStore})` with the queries in D9;
        *   the `agent_progress_read_invalid_range` and
            `agent_progress_read_unavailable` response schemas.
    *   `apps/server/src/agent-protocols.ts` (modify): export
        `LocalDateSchema`.
    *   `apps/server/src/agent-plan-reads.ts` (modify): export
        `cadenceFromRow`, `routineEntryFromRow` and `isoWeekday`.
    *   `apps/server/src/app.ts` (modify): the `agentProgressReadStore`
        option and the route. The route runs `checkAgentProtocolDaysQuery`
        and has 400 and 503 branches.
    *   `apps/server/src/agent-mcp.ts` (modify): the
        `agentProgressReadStore` option and `agent_list_training_days`, with
        the same checks.
    *   `apps/server/src/index.ts` (modify): construct the store from the
        database, the settings store and the catalog store already built
        there, and pass it to both.
    *   `packages/contract/src/agent-skill-reference.ts` (modify): add the
        tool to `AGENT_MCP_TOOL_NAMES` and `progress-training-days` to
        `AGENT_SKILL_COMMAND_NAMES`.
    *   `agent-skills/perennia/scripts/prn-agent.mjs` (modify): the
        `progress-training-days` command.
    *   `agent-skills/perennia/scripts/prn-code.mjs` (modify): a
        `listAgentTrainingDays` method on `PortableOwlAgentClient`.
    *   Regenerate the contract outputs.
35. **`apps/mobile/tool/test_data/test_data_generator.dart`** (modify). The
    generator gains:
    *   the five starter Focuses assigned across its Workouts;
    *   a weekly Routine "Hybrid block" with three slotted templates;
    *   a rotating Routine with two entries;
    *   three Favorite exercises;
    *   Template Links on the Workouts started from those templates;
    *   one Workout started from a template and left with only incomplete
        Sets.

    `apps/mobile/test/tool/test_data_generator_test.dart` (modify) asserts
    each of these exists.
36. **`apps/mobile/test/performance/performance_budget_fixtures.dart`**
    (modify). Add `buildProgressHistoryFixture()`, an in-memory database
    with five years of history:
    *   40 exercises, 10 each with the Record Profiles `repMax`, `maxLoad`,
        `maxDuration` and `fastestPace`;
    *   1 500 Workouts, two weekly Routines and four Focuses;
    *   60 000 Sets, 95% of them complete;
    *   2 000 Readings of one Metric.

    `performance_budget_thresholds.dart` gains `progressTrainingBudget`.
    `performance_budgets_test.dart` asserts it, and
    `apps/mobile/test/performance/README.md` gains its row.
37. **Docs.**
    *   `CONTEXT.md` (modify): add Performed Set, Logged Workout, Training
        Day Status and Trained Day.
    *   `DESIGN.md` (modify):
        *   root navigation: Progress is the Progress Overview;
        *   components: the summary card, the This week row with its
            status icons, the Trained days calendar fill and outline, and
            the Focus color rule.
    *   `AGENTS.md` (modify): the Progress root bullet in the Screen map
        describes Progress Overview.
38. **Tests.**
    *   `apps/mobile/test/features/progress/progress_overview_test.dart`
        (create). It runs against in-memory SQLite with
        `RepositoryProgressFeatureRepository`:
        *   CUJs 1-8, 12 and 14;
        *   period switching;
        *   scroll position kept across tab switches.
    *   `apps/mobile/test/features/progress/this_week_card_test.dart`
        (create), with the stub:
        *   every status icon and its legend entry;
        *   each row of the compared-Routines line table;
        *   the all-zero summary;
        *   the semantics label.
    *   `apps/mobile/test/features/progress/protocols_progress_card_test.dart`
        (create), with the stub and a `protocolsLockStoreProvider` override
        for each lock state:
        *   locked shows no Compound name (search the tree for each);
        *   the locked card is identical with and without Protocols;
        *   unavailable and error show the lock row with no button;
        *   unlocked rows and counts, and the seven-row case;
        *   lock set and no rows shows "No protocol days in this period";
        *   no lock and no rows renders nothing;
        *   absent when `showProtocolsOnToday` is off.
    *   Repository tests against in-memory SQLite:
        *   `apps/mobile/test/data/routine_up_next_repository_test.dart`
            (modify), for `watchWeeklyPlans`: an archived entry, an archived
            template, a null-slot entry, and a Routine with no entries
            (absent);
        *   `apps/mobile/test/data/training_repositories_test.dart`
            (modify), for `watchProgressWorkoutsBetween`: a materialized
            Workout with only incomplete Sets has `performedSetCount` 0; a
            deleted Workout is absent; two Template Links pick the latest;
        *   `apps/mobile/test/features/protocols/consistency_screen_test.dart`
            (modify), where the `watchConsistency` tests live:
            `watchConsistencySummary` counts match `watchConsistency` for
            the same Compound and range.
    *   `apps/mobile/test/app_shell_test.dart` (modify):
        *   the `PerenniaRoot` tests rely on the default stub (item 26);
        *   the accessibility loop's `ProviderScope` adds
            `progressFeatureRepositoryProvider.overrideWith(...)` with a
            populated `StubProgressFeatureRepository`, and the `_NoLockStore`
            override this file already defines;
        *   the `find.text('Body')` finders that target the More tile become
            `find.byKey(ProgressOverview.bodyTrackerTileKey)`, and the
            Health metrics finder likewise.
    *   `apps/server/test/agent-progress-reads.test.mjs` (create):
        *   CUJ 13 against the same data as the app test;
        *   a range of 367 dates, `from` after `to`, `to` after `today`, and
            a `today` two days from UTC (each 400 with
            `agent_progress_read_invalid_range`);
        *   a malformed date (the validator's 400 body);
        *   no store (503);
        *   a Sunday `weekStartDay`;
        *   a Set payload without `is_completed` (not performed);
        *   a Set in a deleted session (ignored).
    *   `apps/server/test/agent-mcp.test.mjs` (modify): the tool list.
    *   `apps/server/test/agent-skill.test.mjs` and
        `packages/contract/test/agent-skill-reference.test.mjs` pass with
        the new names and method.
    *   `performance_budgets_test.dart` (item 36).

### PR 3: Key exercises, New bests and their Agent reads

39. **`packages/golden-vectors/vectors/m37-progress-measure.json` and
    `.schema.json`** (create). `domain: "progress-measure"`. Required cases:
    *   `progress_series`:
        *   one case per Record Profile: `repMax`, `maxLoad`, `maxReps`,
            `maxDuration`, `maxDistance`, `minDuration`, `fastestPace`,
            `minAssistancePerRepCount` (null) and `completionStreak`
            (null);
        *   assisted `repMax` (no points);
        *   a Workout whose only Sets lack the measure (no point);
        *   a Workout with only incomplete Sets (no point);
        *   a Workout mixing complete and incomplete Sets, where the
            incomplete one is heavier (the complete one wins);
        *   equal values across Workouts (not a New Best);
        *   a first Workout;
        *   Sets in kilograms and pounds in one exercise;
        *   a rep-max Set above 10 reps (no e1RM, because the engine's
            existing e1RM formula covers 1 to 10 reps);
        *   a pace Set with zero distance;
        *   two Workouts on one date ordered by `startedAt`;
        *   tied Sets inside a Workout (lower position wins).
    *   `new_bests_between`:
        *   New Bests filtered to a period with earlier history;
        *   New Bests from two exercises on one date (ordered by
            `exerciseId`).
40. **`apps/mobile/lib/domain/analytics/progress_measure.dart`** (create).
    *   `enum ProgressMeasureKind` (Data shapes) and the data classes.
    *   `ProgressSeries? progressSeries({required String exerciseId,
        required ExerciseAnalyticsProfile profile, required
        Iterable<ProgressWorkoutSets> workouts})`.
    *   `List<NewBest> newBestsBetween(Iterable<ProgressSeries> series,
        TrainingDayDate from, TrainingDayDate to)`.
    *   `PeriodBest periodBest(ProgressSeries series, TrainingDayDate from,
        TrainingDayDate to)`.

    It calls `ExerciseAnalyticsEngine.compute` per Workout;
    `exercise_analytics.dart` is not modified.
41. **`apps/server/src/analytics/progress-measure.ts`** (create). Mirror of
    item 40 without `periodBest`.
42. **Runners and CI.** Create
    `apps/mobile/test/domain/progress_measure_golden_test.dart` and
    `apps/server/test/progress-measure.golden.test.mjs`. Register and wire
    them as in item 21, including the `golden_vectors` filter, `ci-local`
    and the vectors README. Add unit tests for `periodBest`: no earlier
    point, equal values, better and worse.
43. **`apps/mobile/lib/features/analytics/repositories/exercise_analytics_repository.dart`**
    (modify). Add:
    *   `Stream<List<ProgressSeries>> watchProgressSeries(Iterable<String>
        exerciseIds)`;
    *   `Stream<List<NewBest>> watchNewBests(TrainingDayDate from,
        TrainingDayDate to)`.

    Both read active exercises (`deletedAt` null) and their Performed Sets.
    They join each Set to its Workout for `localDate` and `startedAt`, and
    drop Sets of deleted Workouts through `_activeWorkoutsById`. The profile
    is built as `ExerciseAnalyticsRepository` builds it today.
    `watchNewBests` runs every exercise's `progressSeries` and
    `newBestsBetween` inside `compute`, passing plain data (the grouped
    `ProgressWorkoutSets` and the profiles) and getting the `NewBest` list
    back.
44. **`progress_feature_repository.dart`** (modify). Add to the interface,
    the real repository and the stub:
    *   `Stream<List<ExerciseRecord>> watchFavorites()`: active Favorite
        exercises, ordered as D8 says;
    *   `Stream<Map<String, String>> watchExerciseNames()`: active
        exercises' names by id;
    *   `watchProgressSeries` and `watchNewBests`, delegating to item 43.

    The real repository also takes an `ExerciseAnalyticsRepository`, read
    from the existing `exerciseAnalyticsRepositoryProvider`.
45. **`progress_controller.dart`** (modify). Add `autoDispose`
    `progressKeyExercisesProvider` (Favorites, their series and
    `periodBest`) and `progressNewBestsProvider` (the New Bests and their
    exercise names), each with a Timeline span.
46. **`apps/mobile/lib/features/progress/widgets/progress_sparkline.dart`**
    (create). `ProgressSparkline({required List<ProgressSparklinePoint>
    points, List<ProgressSparklinePoint> overlay = const [], Set<int>
    markedIndexes = const {}, required Color pointColor, Color?
    overlayColor})`, where `ProgressSparklinePoint` holds `DateTime x` and
    `double y`. It is built on fl_chart's `LineChart` per D8.
47. **`progress_format.dart`** (modify). Add `formatProgressValue` (D8).
48. **Cards** (create). `key_exercises_card.dart` and `new_bests_card.dart`
    in `features/progress/widgets/`, added to `progress_overview.dart` and to
    the externalization test's file list.
49. **`apps/mobile/lib/l10n/app_en.arb`** (modify). The Key exercises and
    New bests strings, measure labels and comparison lines.
50. **Agent server.**
    *   `agent-progress-reads.ts` (modify):
        *   `listAgentNewBests`, its schemas and route;
        *   the store methods `readNewBests` and `readExerciseProgressSets`,
            with the loading rules in D9.
    *   `agent-read-surface.ts` (modify):
        *   export `agentAnalyticsProfile(exercise: AgentExercise)`,
            extracted from `buildAgentExerciseAnalyticsResponse`;
        *   add `progressSeries` (nullable) to
            `AgentExerciseAnalyticsResponseSchema`;
        *   give the builder an optional `progressSeries` argument that
            defaults to null.
    *   `app.ts` and `agent-mcp.ts` (modify):
        *   register `listAgentNewBests` and `agent_list_new_bests`;
        *   in the exercise analytics handlers, call
            `readExerciseProgressSets` and `progressSeries` when the
            progress store is configured, and pass the result to the
            builder.
    *   `agent-skill-reference.ts`, `prn-agent.mjs` and `prn-code.mjs`
        (modify): the tool, the `progress-new-bests` command and the
        `listAgentNewBests` method.
    *   Regenerate the contract outputs.
51. **`performance_budget_thresholds.dart` and
    `performance_budgets_test.dart`** (modify). Add
    `progressNewBestsBudget` over the item 36 fixture, plus its README row.
52. **`CONTEXT.md`** (modify). Add Progress Measure and New Best.
53. **Tests.**
    *   `apps/mobile/test/features/progress/key_exercises_card_test.dart`
        and `new_bests_card_test.dart` (create), with the stub:
        *   each comparison-line case;
        *   the tile with no point in the period;
        *   the two empty states;
        *   the "e1RM" prefix;
        *   each date-format case.
    *   `apps/mobile/test/features/progress/progress_format_test.dart`
        (create): each row of D8's Values table in both unit systems, and
        differences under and over a minute.
    *   `apps/mobile/test/features/progress/progress_sparkline_test.dart`
        (create):
        *   the y range is not zero-based;
        *   uneven times are placed by time;
        *   marked points render.
    *   `apps/mobile/test/features/analytics/exercise_analytics_repository_test.dart`
        (modify):
        *   incomplete Sets and Sets of deleted Workouts are excluded;
        *   an archived exercise has no series and no New Bests.
    *   `progress_overview_test.dart` (modify): CUJs 9 and 10, and an
        abandoned planned Workout adds no New Best. Pumps that wait on
        `watchNewBests` run inside `tester.runAsync`.
    *   `apps/server/test/agent-progress-reads.test.mjs` (modify):
        *   New Bests for CUJ 9;
        *   an archived user exercise is skipped;
        *   a Set in a deleted session is ignored;
        *   the range errors.
    *   `apps/server/test/agent-read-surface.test.mjs` (modify):
        `progressSeries` covers more than 200 Sets of history, and is null
        without the progress store.
    *   `agent-mcp.test.mjs` (modify): the tool list.

### PR 4: Body and `includeTrend`

54. **`packages/golden-vectors/vectors/m37-metric-trend.json` and
    `.schema.json`** (create). `domain: "metric-trend"`, with
    `tolerance: 1e-9`. `metric_trend` cases:
    *   one Reading;
    *   daily Readings;
    *   a 5-day gap;
    *   two Readings ten minutes apart;
    *   a non-finite value skipped;
    *   equal timestamps ordered by id;
    *   unsorted input;
    *   a null value.
55. **`apps/mobile/lib/domain/metrics/metric_trend.dart`** (create).
    `List<TrendPoint> metricTrend(Iterable<TrendInput> readings)` and the
    Dart-only `double? trendChange(List<TrendPoint> points, DateTime start,
    DateTime end)`.
56. **`apps/server/src/analytics/metric-trend.ts`** (create). Mirror of
    `metricTrend`.
57. **Runners and CI.** Create
    `apps/mobile/test/domain/metric_trend_golden_test.dart` and
    `apps/server/test/metric-trend.golden.test.mjs`, wired as in item 21,
    with the tolerance rule from Data shapes. Add unit tests for
    `trendChange`:
    *   with an earlier point;
    *   without an earlier point;
    *   an empty period;
    *   a Reading exactly at `start`.
58. **`progress_feature_repository.dart`** (modify). Add to the interface,
    the real repository and the stub:
    *   `Stream<List<MeasurementRecord>> watchCuratedMeasurements()`,
        delegating to `MeasurementRepository.watchCuratedActive`;
    *   `Stream<List<MeasurementHistoryEntry>>
        watchMeasurementEntries(String measurementId)`, delegating to
        `MeasurementRepository.watchHistoryEntries(measurementId: id)`.
59. **`progress_controller.dart`** (modify). Add the `autoDispose`
    `progressBodyProvider`, emitting `List<ProgressBodyRow>` under a
    Timeline span named `progress.body`. For the curated measurements, it:
    *   watches a `StreamProvider.autoDispose.family` of each
        measurement's entries, keyed by measurement id;
    *   maps each entry to `TrendInput` (D5) and runs `metricTrend`;
    *   keeps measurements with at least one Reading in the period;
    *   computes `trendChange` with `start` and `end` built from the period's
        dates in the device zone;
    *   takes `latestTrend` from the last `TrendPoint` in the period.
60. **`apps/mobile/lib/features/progress/widgets/body_card.dart`** (create).
    It uses `ProgressSparkline` with the Trend as the overlay. Add it to
    `progress_overview.dart`, to the externalization test's file list, and
    its strings to `app_en.arb`.
61. **Agent server.**
    *   `apps/server/src/agent-metrics.ts` (modify):
        *   the readings query gains `includeTrend` (D9);
        *   `AgentMetricReadingListItemSchema` gains optional `trendValue`;
        *   `createDrizzleAgentMetricStore`'s `listMetricReadings` loads all
            live readings of each Metric in the page when `includeTrend` is
            `"true"`, maps them to `TrendInput` (D5), runs `metricTrend`,
            and attaches `trendValue` after the `fields` projection.
    *   `agent-mcp.ts` (modify): add `includeTrend` to the readings tool's
        input schema. The shared store does the rest.
    *   Regenerate the contract outputs.
62. **`performance_budget_thresholds.dart` and
    `performance_budgets_test.dart`** (modify). Add `progressTrendBudget`
    over the item 36 fixture's Readings, plus its README row.
63. **`CONTEXT.md`** (modify). Add Trend.
64. **Tests.**
    *   `apps/mobile/test/features/progress/body_card_test.dart` (create):
        *   CUJ 11;
        *   the empty state;
        *   the change label with and without an earlier Reading;
        *   "No change".
    *   `apps/server/test/agent-metrics.test.mjs` (modify):
        *   `includeTrend=true` on a page whose Metric has older readings
            outside the page;
        *   `includeTrend=true` with `fields` set (still carries
            `trendValue`);
        *   `includeTrend=false` (no `trendValue`);
        *   a reading whose value is only in `valueJson.value` (carries
            `trendValue`);
        *   an archived reading with `includeArchived` (no `trendValue`).
65. **This spec** (modify). Status Current once PR 4 merges.

## Verification Plan

*   **CI gate.** `pnpm ci:local --changed` is green for every pull request;
    it selects the jobs from the changed paths, as hosted CI does. Each pull
    request that adds a server golden runner also adds it to the
    `golden_vectors` filter in `.github/workflows/ci.yml` and to
    `tools/ci-local.mjs` (items 21, 42 and 57).
*   **Cross-language.** Every m37 case passes in both languages. `m4` and
    `m33-plan-validation` still pass unchanged.
*   **Migration.** The schema snapshot test upgrades a v62 database with a
    Focus row to v63.
*   **Sync.**
    *   A Focus recolored on one device arrives on another.
    *   A push from a client without `color_hex` keeps the stored color on
        the server (`focus-sync.test.mjs`) and on devices
        (`focus_repository_test.dart`).
    *   An undo written before the upgrade still applies.
*   **Standing scenario.** `focus_recolor_reopen_test.dart` kills the
    database at two points during a recolor and reopens it. Progress is
    read-only, and no other new write exists.
*   **Accessibility.** The Progress guideline tests in `app_shell_test.dart`,
    with every card populated through the stub.
*   **Speed.** The budgets in the Non-Functional Requirements, each added to
    `performance_budgets_test.dart` in the pull request that adds its core.
*   **Manual.** Run the emulator with `pnpm test-data` (extended in item 35)
    and check each CUJ's "Then" in both themes, at 4 wk, 12 wk and 1 yr.

--------------------------------------------------------------------------------

<!-- Provenance: Indicates initial structural drafting via EGM. -->

*Drafted with EGM*
