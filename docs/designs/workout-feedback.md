# Workout Feedback

*   **Author:** Leonardo Pinheiro
*   **Status:** Approved
*   **Date:** 2026-11-04

--------------------------------------------------------------------------------

Read first: [CONTEXT.md](../../CONTEXT.md) for the terms used here,
[ARCHITECTURE.md](../../ARCHITECTURE.md) for the app's layering,
[AGENTS.md](../../AGENTS.md) for the invariants and the gate, and
[DESIGN.md](../../DESIGN.md) for the tokens. This spec builds on
[Plan-Guided Logging](plan-guided-logging.md), which owns the Training Screen's
Log set, the rest strip and Undo.

## Overview

This spec changes how the app tells the lifter what just happened and what
comes next during a Workout. It covers three moments and one style rule for
the rest of the app:

1.  **After Log set.** The confirmation and its Undo move out of a floating
    message and into the row the rest strip occupies, in the Training Screen's
    pinned bottom area. The rest countdown takes the row back when the message
    ends.
2.  **During a rest.** The rest timer gets a get-ready cue 10 seconds before
    the end, a 3-2-1 countdown that matches the seconds on screen, an end tone,
    and a "Rest over" state. While the Training Screen is open, the cues play
    in the app (sound, vibration and a visible change) and no notification
    appears. Anywhere else, the system notification carries them.
3.  **At Finish.** Finish Workout opens a summary sheet instead of a dialog
    followed by a message: duration, sets, exercises and New Bests, an
    `Update "Lower B"` row that lists the changes one per line ("Add Dips",
    "Deadlift: sets changed") instead of the "+ / − / ~" shorthand, a
    "Copy summary" row, and Done.
4.  **Everywhere else.** Every other message uses one SnackBar style built
    from DESIGN.md tokens.

No schema, sync, contract, validation or golden vector change. The work is in
the app's widgets, its theme, and the native timer code on Android and iOS.

## The Problem

A lifter logs a set, puts the phone down, rests, and picks it up again for the
next set. Today the feedback around that loop works against them. The points
below were seen on an Android emulator against 0.2.0. The iOS points are read
from the code (`AppDelegate`'s `willPresent` returns `.banner` for timer
notifications) and from Flutter's documentation for `SystemSoundType.alert`.

*   **The confirmation covers the form.** "Set 3 logged · Undo" floats at a
    fixed 192 px above the bottom of the Training Screen. The pinned area under
    it changes height (Log set, or Update, Delete and Not done), so the message
    lands on the Comment field or the Rest after row while the next set is
    being entered.
*   **It does not look like the app.** The messages use Material's default
    SnackBar with no theme. In the light theme the Undo label is `#06262B` on
    `#1A2126`, about 1.0:1 measured from the emulator screenshot, which fails
    the WCAG AA rule in DESIGN.md.
*   **The rest ends silently while the app is open.** The end cue asks Flutter
    for the system alert sound, which Flutter ignores on Android and iOS. The
    3-second cue is a selection click plus a touch sound that Android plays
    only when system touch sounds are on. The app's own tones play only from
    the background notification. A lifter with the phone face-up on a bench
    gets one short vibration at 0:00.
*   **There is no warning early enough to get ready.** The earliest cue comes
    at 0:03, which is too late to stand up, chalk and set up. The lifter
    wants a cue about 10 seconds out, as other fitness apps give.
*   **The cue that does fire lands on top of the app.** With the app open, the
    background notification still posts, so Android shows a heads-up (and iOS
    a banner) over the app bar at 0:03 and 0:00.
*   **There is no "rest over" state.** At 0:00 the strip goes straight back to
    "Start rest". A lifter who looks up a few seconds late cannot tell that the
    rest ended, or how long ago.
*   **Finish ends in two pieces.** Finish returns to Today and opens a dialog,
    `Update "Lower B"?`, whose body is a diff shorthand ("~ Deadlift"). A
    4-second "Workout finished · Share" message shows behind the dialog.

Until [#101](https://github.com/perennia-fit/perennia/pull/101), every message
with an action also stayed on screen until the next message replaced it,
because of a Flutter default. That pull request fixes it and is a prerequisite
(see [Prerequisites](#prerequisites)); it is not part of this design.

## Goals

*   **No message overlaps the logging form.** On the Training Screen, no
    message covers the Track form or the set list at any text size, with any
    pinned buttons showing.
*   **The set confirmation appears within one frame.** "Set *n* logged"
    appears within one frame of Log set (the invariant "Set save confirms
    within one frame"), whatever phase the rest timer is in. It is keyed by
    `saveSetConfirmationKey`, so the existing performance test still measures
    it.
*   **Undo lasts 4 seconds, in the pinned area.** The Log set Undo is
    reachable for 4 seconds, within thumb reach, and goes when its message ends,
    is tapped, or the screen closes.
*   **An audible and felt cue before the rest ends.** With the Training Screen
    open, a rest longer than 15 seconds gives a cue 10 seconds before the end,
    beeps at 3, 2 and 1 in time with the seconds shown, and a distinct end
    tone. Each comes with a vibration and a visible change on the strip.
*   **One cue per moment.** While the Training Screen is open and the app is
    in the foreground, no system notification fires for these cues. Otherwise
    the notification carries them, naming the exercise and set.
*   **The end of a rest is visible.** After 0:00 the strip shows "Rest over"
    and how long ago, until the next Set is logged, Stop, or 5 minutes pass.
*   **Finish has one ending.** A summary sheet shows what the Workout was, lets
    the user update its template and copy a summary, and closes back to the
    screen that opened the Workout.
*   **Every message uses the DESIGN.md `notice` style.** Every SnackBar in the
    app takes its colours, shape and type from the `notice` component, and its
    text and action pass WCAG AA (4.5:1) in both themes.

## Non-Goals

*   **No change to logging behaviour.** Log set, carry-forward, the Current
    Set, Remembered Rest, Undo's effect, and the rest strip's existing controls
    (−15 s, +15 s, Stop, the volume sheet) stay as Plan-Guided Logging specifies
    them.
*   **The Rest timer sounds setting keeps its meaning, and now also works on
    Android 8 and later.** Settings › Logging › Rest timer sounds
    (`restTimerSoundsEnabled`) still means: off silences the tones and the
    vibration, in the app and in notifications. The strip's visual changes
    show either way. Today, on Android 8 and later, off does not silence
    notifications, because the channel's sound wins over the per-notification
    mute. This spec fixes that with silent channels
    ([part 4](#4-cues-and-notifications)); the meaning does not change.
*   **No change to template divergence.** What counts as a change to the
    template, the shared `TemplateDivergenceResult` type, and what "Update"
    writes stay as they are. Only how the changes are presented changes.
*   **No celebration.** No streaks, confetti or motivational copy at Finish. New
    Bests are the only highlight, as everywhere else.
*   **No new sync or agent surface.** Cues and messages are device behaviour.
    Nothing new is stored, synced or exposed to agents.
*   **No interval timer.** The app has no interval timer screen today
    (`TimerBackgroundKind.interval` has no caller), so only the rest timer uses
    these cues and tones.
*   **No change to Protocol reminders.** They keep their own notification
    channel and presentation.

## Prerequisites

[#101](https://github.com/perennia-fit/perennia/pull/101) ("let confirmations
with Undo close again") merges first. This spec starts from main with it. What
it provides, and what this spec relies on:

*   **Every SnackBar with an action passes `persist: false`.** That covers
    `showTrainingSnackBar` and the Finish SnackBar, so their 4 s (with Undo)
    and 2 s durations hold.
*   **`showTrainingSnackBar` closes with its screen.** Its signature is
    `showTrainingSnackBar(ScaffoldMessengerState messenger, String message,
    {Key? key, EdgeInsetsGeometry? margin, ModalRoute<Object?>? route, String?
    undoLabel, VoidCallback? onUndo})`. With `route`, the SnackBar closes when
    that route is popped. Covering the route with another one keeps it.
*   **`undoTrainingBatch(repositories, messenger, l10n, batchId,
    {EdgeInsetsGeometry? margin, ModalRoute<Object?>? route})`** passes both
    on to the conflict message.
*   **`replaceExercise` reads `ModalRoute.of(context)`** and passes it as
    `route`.
*   **Two tests in `apps/mobile/test/features/training/training_screen_test.dart`**
    check that the Log set confirmation goes after 4 s and when the Training
    Screen closes.

## Open Questions

No open questions. Settled while drafting:

*   **Audio stream for in-app cues: the media stream, with other audio
    ducked.** A lifter wearing earbuds hears a notification-stream cue only
    from the phone's speaker, or not at all. The cost: the cue follows the
    media volume and ignores the iPhone's silent switch. The Rest timer sounds
    setting is the way to silence it.
*   **"Rest over" returns to idle 5 minutes after the deadline,** so a strip
    left alone does not read "+58:12".
*   **Swiping the Finish sheet away does what Done does.** The Workout is
    already finished when the sheet opens. An accidental Finish is undone with
    Resume on the Workout screen, as today.

## Critical User Journeys (CUJs)

### CUJ 1: Log a set and keep typing

*   **Given**: the Training Screen on Deadlift, Set 3 of 4 current, the
    rest after set to 2:00.
*   **When**: the user taps Log set, then taps the Reps field to change the
    next set.
*   **Then**:
    *   In the same frame as the tap, the strip's row reads "Set 3 logged"
        with Undo.
    *   Nothing overlaps the set list or the form.
    *   When the keyboard opens, the pinned area rides above it, as today.
    *   After 4 seconds the row crossfades to "Rest 1:56".

### CUJ 2: Undo from the status row

*   **Given**: "Set 3 logged · 2 later sets updated" with Undo is showing.
*   **When**: the user taps Undo within 4 seconds.
*   **Then**:
    *   The message clears at once.
    *   The Set returns to planned and the carried loads go back.
    *   The rest it started is cancelled (as Plan-Guided Logging specifies),
        and the row shows "Start rest".
    *   If those Sets changed since, the row instead reads "Couldn't undo:
        changed since" for 2 seconds.

### CUJ 3: Get ready with the phone on the bench

*   **Given**:
    *   a 2:00 rest running on the Training Screen, with the app open;
    *   the phone face-up, earbuds playing music;
    *   Rest timer sounds on.
*   **When**: the rest reaches 0:10, then 0:03, then 0:00.
*   **Then**:
    *   **At 0:10:** the music ducks (its volume drops while the tone plays),
        the get-ready tone plays, and the phone gives a medium vibration. The
        strip gets a cyan border and reads "Get ready · 0:10". The Current row
        above already shows Set 4.
    *   **From 0:03:** three beeps sound as the strip shows 0:03, 0:02 and
        0:01, with a light vibration on each.
    *   **At 0:00:** the end tone plays with two strong vibrations, and the
        strip reads "Rest over · +0:00", counting up.
    *   No system notification appears at any point.

### CUJ 4: The same rest with the app in the background

*   **Given**: the same rest, the user switched to a music app at 1:30.
*   **When**: the rest reaches 0:10, 0:03 and 0:00.
*   **Then**:
    *   **At 0:10:** a notification "Get ready · Deadlift · Set 4" with the
        get-ready tone.
    *   **At 0:03:** "Deadlift · Set 4 in 0:03" with the 3-2-1 tone.
    *   **At 0:00:** "Rest over".
    *   This happens on Android and iOS.
    *   Opening the app after 0:00 shows "Rest over · +0:07" on the strip and
        plays nothing again.

### CUJ 5: Finish a Workout that drifted from its template

*   **Given**:
    *   Lower B, started from its template, which plans Deadlift, Leg Press
        and Hip Thrust at 3 sets each;
    *   the user logged 4 Deadlift sets and 3 Leg Press sets, and removed Hip
        Thrust from the Workout;
    *   the Deadlift sets include a New Best for its heaviest load.
*   **When**: the user taps Finish Workout.
*   **Then**:
    *   The Workout is finished, and a sheet opens over it.
    *   The sheet shows "Lower B", "32 min · 7 of 7 sets · 2 exercises", and
        under New bests "Deadlift · heaviest 140 kg" with the trophy marker.
    *   A row reads `Update "Lower B"`, with "Remove Hip Thrust" and "Deadlift:
        sets changed" under it.
    *   Rows "Copy summary" and Done follow.
    *   Done returns to the screen that opened the Workout. No dialog and no
        message appear.

### CUJ 6: A message elsewhere in the app

*   **Given**: Today, in the light theme.
*   **When**: the user copies a Workout summary from a Workout's menu.
*   **Then**: "Workout summary copied" appears in the `notice` style, a dark
    bar with rounded corners, above the Log button and the navigation bar. It
    closes after 2 seconds.

## Technical Plan (Architecture)

The design has five parts, in four pull requests merged in order (listed in
the [Detailed Implementation Plan](#detailed-implementation-plan)):

| Part | Pull request |
| :--- | :--- |
| [1. One message style](#1-one-message-style) | 1 |
| [2. The status row](#2-the-status-row) | 2 |
| [3. Rest phases](#3-rest-phases) | 3 |
| [4. Cues and notifications](#4-cues-and-notifications) | 3 |
| [5. Finish summary](#5-finish-summary) | 4 |

### 1. One message style

`AppTheme` sets `snackBarTheme` for both themes from a new DESIGN.md
component, `notice`:

| Property | Token |
| :--- | :--- |
| background | `chrome-dark` (both themes) |
| border | 1 px `divider-dark`, so it separates from the dark background |
| text | `text-primary-dark`, `body` style |
| action | `primary` |
| shape | `rounded.md` |
| elevation | 0 (DESIGN.md uses borders, not shadows, at this level) |
| behaviour | floating; inset `spacing.base` on every side |

The bar is dark in the light theme too. One pair of colours then passes AA in
both themes: `text-primary-dark` on `chrome-dark` is about 16:1, `primary` on
`chrome-dark` about 8:1. A light bar would need a new, darker cyan for its
action (see [Alternative J](#alternative-j-a-light-snackbar-in-the-light-theme)).

A floating SnackBar sits above a Scaffold's bottom navigation bar and floating
action button, so no screen sets its own margin. The one exception is the
Training Screen, which lifts SnackBars from other screens above its pinned area
([part 2](#2-the-status-row)).

### 2. The status row

Today the Training Screen shows its messages as SnackBars floated at a fixed
margin. After this change it shows them in the row the rest strip already
holds, between the form's scroll view and the action buttons. The rest strip
has to stay mounted in that slot across exercise switches and Update mode,
because it owns the rest timer's ticker, cues and background schedule
(Plan-Guided Logging). So the confirmation is drawn **by the rest strip**,
not by a widget that replaces it.

*   **One message at a time.** The screen holds one `TrainingConfirmation?` in
    its state: the message, an optional Undo, and a sequence number. It lasts
    4 s with Undo and 2 s without, the durations used today. Showing one
    replaces the previous one (a new sequence number) and restarts a `Timer`
    that clears it. Tapping Undo clears it at once.
*   **What the row shows.** While a confirmation lasts, the strip shows it.
    The rest of the time it shows the rest phase ([part 3](#3-rest-phases)).
    Cues keep playing while a confirmation shows; the phase is drawn again when
    the confirmation ends.
*   **Every Training Screen message moves to the row:**
    *   Set logged, with and without carried sets;
    *   Set not logged, Set not updated, Set deleted;
    *   Planned set removed, Round added, Couldn't undo;
    *   the Replace results, when Replace starts from this screen;
    *   "Background timer alerts are off", shown when a rest starts with
        notification permission denied.
*   **"Background timer alerts are off" shows once per app run.** A static
    flag in `notifyIfBackgroundAlertsDenied` remembers that it was shown. It
    never replaces a confirmation with Undo: if one is showing, the message
    waits and shows when that one ends. Without these two rules, a lifter who
    denied notifications would lose Undo on every Log set.
*   **Within one frame.** Log set sets the confirmation with `setState` before
    it awaits the write, as it calls `showSnackBar` today. Its message text
    carries `TrainingScreen.saveSetConfirmationKey`.
*   **Swapping message and countdown.**
    *   The swap is a 150 ms crossfade (`AnimatedSwitcher`), with no animation
        when `MediaQuery.disableAnimations` is set.
    *   The switcher's child is keyed by the sequence number. The key
        `saveSetConfirmationKey` sits on the message `Text` inside the child,
        so two children never hold it as siblings.
    *   Log set first shows "Set *n* logged" and then the version with Undo
        (Plan-Guided Logging's steps 4 and 7). That second message keeps the
        same sequence number, so it updates in place with no transition.
    *   For 300 ms after a message with Undo ends (a double tap's length), what
        replaced it ignores taps. Undo draws where Stop does, so without this
        the second tap of a double tap on Undo, or one tap a moment too late,
        would cancel the rest with no way back. A tap inside the crossfade
        reaches the outgoing Undo, which runs once.
*   **Accessibility.** Only the confirmation text is a live region
    (`Semantics(liveRegion: true)`), so a screen reader reads each message once
    and never the countdown digits. At large text sizes the row grows to two
    lines; the message wraps and Undo stays a 48 dp target.
*   **Replace.** `replaceExercise` stops taking `snackBarMargin`. It takes a
    `ShowTrainingConfirmation` function instead. The Training Screen passes its
    own; the Workout screen passes one that shows a SnackBar with `route`
    ([Prerequisites](#prerequisites)).
*   **SnackBars from other screens.** The Workout screen's "Replaced · Undo"
    follows the user onto a Training Screen they open within 4 seconds, as
    Plan-Guided Logging specifies.
    *   The Training Screen wraps its `Scaffold` in a `Theme` whose
        `snackBarTheme.insetPadding` adds the pinned area's height to the
        bottom inset, so such a SnackBar floats above the strip.
    *   The pinned block (the strip, the spacing around it and the action
        buttons) is one `Column` wrapped in a small render-object reporter.
        After every layout, including the first, the reporter writes the
        block's height to a `ValueNotifier<double>` in a post-frame callback
        (a write during layout would throw). A `ValueListenableBuilder` above
        the `Theme` rebuilds the inset when the height changes.
    *   `_snackBarMargin` is deleted.

```text
 ┌ Training Screen ───────────────────────┐
 │ set list + Track form (scrolls)        │
 ├────────────────────────────────────────┤  ← floating SnackBars from
 │ RestStrip                              │     other screens sit above here
 │   confirmation (2–4 s)  else  phase    │
 ├────────────────────────────────────────┤
 │ Log set  |  Update · Delete · Not done │
 └────────────────────────────────────────┘
       (keyboard opens below; this block rides above it)
```

### 3. Rest phases

A pure function decides what the strip shows. It lives in
`apps/mobile/lib/features/training/services/rest_cues.dart` and takes the
timer row (`RestTimerRecord`), the Workout's newest Performed Set, and a clock
reading, so tests drive it without a ticker:

```text
restPhaseAt(timer, newestPerformed, now):
  if timer == null or timer.status == canceled           -> idle
  remaining = timer.deadlineAt - now
  if remaining > 0 and timer.status == running:
     if timer.duration > 15 s and remaining <= 10 s and remaining > 3 s
                                                         -> getReady(remaining)
     if remaining <= 3 s                                 -> countdown(remaining)
     else                                                -> resting(remaining)
  // at or past the deadline, status running or expired
  elapsed = now - timer.deadlineAt
  if elapsed > 5 min                                     -> idle
  if newestPerformed != null
     and newestPerformed.id != timer.sourceSetId
     and newestPerformed.performedAt > timer.startedAt   -> idle
  -> over(elapsed)
```

*   **Why `expired` counts as over.** `RestTimerRepository.markAlertFired` sets
    the status to `expired` along with `alertFiredAt`. Without that rule, the
    strip would drop to idle the moment it marks the end.
*   **Why a later Set ends Rest over.** With Rest after Off, Log set starts no
    timer and leaves the previous one. A Set logged after the timer started,
    other than the Set that started it, means the lifter has moved on.

| Phase | Strip |
| :--- | :--- |
| resting | "Rest 1:42", −15 s, +15 s, Stop, and a 2 dp elapsed bar in `primary` on a `divider` track along the strip's bottom edge |
| getReady | the strip's border becomes 2 dp `primary`; "Get ready · 0:10" with "Get ready" in `textPrimary` weight 600; −15 s, +15 s, Stop |
| countdown | as getReady, with the remaining seconds |
| over | `surface` background; "Rest over" in `textPrimary`, "+0:12" in `textSecondary`, counting up; Stop clears it |
| idle | "Start rest", as today |

*   **No new cyan element.** DESIGN.md asks for Signal Cyan on "exactly one
    action or state per screen", and the Current row's highlight and the
    strip's elapsed bar already use it today. Get ready adds no cyan fill: the
    strip's elapsed bar and its Get-ready border count as one cyan element,
    separate from the Current row's highlight, and no other part of the strip
    is cyan. Colour is never the only signal:
    every phase changes the words.
*   **Phase changes are announced once** with
    `SemanticsService.sendAnnouncement(View.of(context), text,
    Directionality.of(context))` ("Get ready", "Rest over"), so screen readers
    hear the phase, not each second.
*   **The display ticker** is aligned to whole seconds of `remaining`. Its first
    tick comes at the next whole-second boundary, then one every second, so the
    digits change in step with the cues.
*   **The digits round up.** The strip shows `remaining` rounded up to whole
    seconds, as the native `formatRemaining` does. A `Timer` never fires early,
    so rounding down would show "0:02" as the 0:03 beep plays.
    `formatRestDuration` keeps its rounding, because the Rest after field uses
    it.
*   **No next-set label on the strip.** Get ready reads "Get ready · 0:10".
    The Current row and the context line's "Next:" already show what comes
    next, and a label on the strip would repeat them.
*   **Rest over survives kill-and-reopen,** since it is derived from the row.
*   **Marking the end.** Whenever the strip, while the app is visible
    ([part 4](#4-cues-and-notifications)), sees a row with status `running` at
    or past its deadline, it writes `markAlertFired` and cancels the
    background schedule. It checks on every tick and when the app comes back.
    This one rule covers the end reached in the app, an end that passed while
    the app was in the background, and a reopen after 0:00. Marking plays
    nothing; only the end cue ([part 4](#4-cues-and-notifications)) plays a
    tone.

### 4. Cues and notifications

**Cues are scheduled from the deadline.** A plain Dart class,
`RestCueScheduler`, owns the cue timing. It reads time only through
`clock.now()` (`package:clock`), so tests run it under `fakeAsync` with no
widget and no database. When the strip sees a running timer whose
`(id, deadlineAt)` differs from the one it armed (a new timer, or a new
deadline after ±15 s), the scheduler arms one-shot `Timer`s at these offsets
from `deadlineAt`:

| Offset | Cue |
| :--- | :--- |
| −10 s, only for rests longer than 15 s | `getReady` |
| −3 s | `countdown` (the 3-2-1 tone and the first vibration) |
| −2 s and −1 s | `tick` |
| 0 | `end` |

*   **Arming.** A cue is armed if its time is at most 1 s in the past, and
    skipped if it is further back. So −15 s that brings the deadline to now
    (`adjust` sets a deadline at or before now to exactly now) still arms the
    end cue. Stop, a new timer and `dispose` cancel the armed cues.
*   **Playing.** When an armed cue fires, it plays if it fires at most 1 s late
    (`cueLateLimit`) and `canPlay()` holds. Otherwise it is skipped, and the
    system notification covers that moment, as below.
*   **Opening on a running rest.** A strip that opens part-way through a rest
    therefore plays only the cues still ahead. A reopen at 0:05 plays the 3-2-1
    and the end but not Get ready. No cue is detected from what a frame
    happens to see, so resuming the app never replays a cue.
*   **The end.** Playing the end cue does not write anything. The end is
    marked by the rule in [part 3](#3-rest-phases), which sees the row at its
    deadline on the same tick.

The strip creates one `RestCueScheduler` and gives it two functions:

*   `canPlay`: the app is visible, the strip's route is current
    (`ModalRoute.isCurrent`), and Rest timer sounds is on;
*   `onCue`: calls `TimerCuePlayer.play(cue, volume: timer.alertVolume)`.

**"Visible" means the same thing on every side.** The app is visible when the
lifter can see it:

*   **Dart:** the lifecycle state is anything but `paused` or `hidden`. So
    `inactive` (the notification shade, Control Center, split screen) still
    counts as visible. The first value is read from
    `WidgetsBinding.instance.lifecycleState`, then an `AppLifecycleListener`
    keeps it current.
*   **Android:** `MainActivity` is between `onStart` and `onStop`, kept in a
    static `isStarted`.
*   **iOS:** `willPresent` runs only while the app is in the foreground, so a
    call to it already means visible.

**Who cues.** At each threshold exactly one side plays:

*   **The app plays it** when the app is visible and a strip on the current
    route is showing that rest.
*   **The system notification plays it** otherwise: in the background, on a
    locked screen, or on another screen of the app (where no strip is
    current, and the notification is the only cue left).

Dart tells native whether a strip is current with one boolean,
`setInAppTimerCues {active: bool}`:

*   **`RestCueOwner`,** a Riverpod provider, keeps one entry per mounted
    strip. On every tick, each strip updates its entry to whether its route is
    current. The router can push a second Training Screen over the first, and
    only the top one is current, so only one strip plays.
*   `RestCueOwner` sends `active = any entry is true` each time that value
    changes, and `false` when the last strip disposes.
*   **Native resets the value to false when the Flutter engine starts**
    (`configureFlutterEngine` on Android, `didInitializeImplicitFlutterEngine`
    on iOS). A value left from an engine that died never silences later
    rests.
*   **Native posts a cue's notification** unless the app is visible and the
    value is true.

**Playing a cue.** `TimerCuePlayer` has two methods, `prepare()` and
`play(TimerCue cue, {required double volume})`, where `TimerCue` is
`getReady | countdown | tick | end`. The default implementation calls the
native timer channel (`perennia/timer_background`):

*   **`prepareCues`** loads the tone files. It is called once per app run,
    when a strip first mounts, so the first cue is never lost to a load.
*   **`playCue {cue: 'getReady'|'countdown'|'tick'|'end', volume: 0..1}`**
    plays the cue's tone (none for `tick`) and its vibration, and returns
    null. An unknown cue is ignored.

The tone and vibration for each cue:

| Cue | Tone | Android vibration | iOS haptic |
| :--- | :--- | :--- | :--- |
| getReady | `get_ready` | 80 ms | `UIImpactFeedbackGenerator(.medium)` |
| countdown | `prepare_beep` (blips at 0, 1 and 2 s) | 40 ms | `.light` |
| tick | none | 40 ms | `.light` |
| end | `timer_complete` | 200 ms, 150 ms gap, 200 ms | `.heavy` twice, 150 ms apart |

*   **Android.**
    *   One `MediaPlayer` per tone, with `AudioAttributes(USAGE_MEDIA,
        CONTENT_TYPE_SONIFICATION)`, prepared in `prepareCues` and released
        in `MainActivity.cleanUpFlutterEngine`.
    *   Before a tone plays, the player requests transient audio focus with
        `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`, so other audio ducks (its volume
        drops while the tone plays). It abandons focus in the player's
        `OnCompletionListener`. `tick` has no tone and requests no focus.
    *   On API 26 and later, focus uses an `AudioFocusRequest`. Below 26 it
        uses `requestAudioFocus(listener, STREAM_MUSIC,
        AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)`.
    *   Vibration: API 31 and later take the vibrator from
        `VibratorManager.defaultVibrator`; API 26–30 use `Vibrator` with
        `VibrationEffect.createWaveform`; below 26, `vibrate(LongArray, -1)`.
        The manifest gains `android.permission.VIBRATE`, a normal permission
        with no prompt.
*   **iOS.**
    *   One `AVAudioPlayer` per tone, prepared in `prepareCues`.
    *   Before a tone plays, the audio session is set to category `.playback`
        with `[.mixWithOthers, .duckOthers]` and activated.
    *   The session is deactivated with `.notifyOthersOnDeactivation` in
        `audioPlayerDidFinishPlaying`, never while a tone is playing.
*   `SystemSound` is no longer used by the rest timer.

**The tones.** `tools/gen-timer-sounds.mjs` changes, and is run from the
repository root with ffmpeg on PATH (`node tools/gen-timer-sounds.mjs`). It
writes the `.ogg` and `.caf` files, and deletes each Android `.wav` after
transcoding it (a `.wav` next to an `.ogg` of the same name is a duplicate
resource and fails the build):

*   **`prepare_beep` (3-2-1):** three 90 ms, 1200 Hz blips starting at 0 ms,
    1000 ms and 2000 ms (today they are 200 ms apart). Played at 0:03, it
    sounds at 3, 2 and 1, in the app and from the background notification
    alike.
*   **New `get_ready`:** two 120 ms, 660 Hz notes at gain 0.35, 120 ms apart.
    It is lower and quieter than both other cues. The files are
    `get_ready.ogg` on Android and `GetReady.caf` on iOS.
*   **`timer_complete`** is unchanged.

**Android notification channels.** A channel's sound can't change after the
channel is created. Today's channels address their sound by resource id
(`android.resource://<pkg>/<id>`), and aapt2 assigns `R.raw` ids in name
order, so adding `get_ready` shifts the ids of `prepare_beep` and
`timer_complete`. An updated install would play the wrong tones on the old
channels. So the sounded channels get new ids, and their sound is addressed by
name (`android.resource://<pkg>/raw/<name>`), which no later file can shift:

| Channel | Sound | Silent twin |
| :--- | :--- | :--- |
| `workout_timer_get_ready_v1` | `get_ready` | `workout_timer_get_ready_v1_silent` |
| `workout_timer_prepare_v3` | `prepare_beep` | `workout_timer_prepare_v3_silent` |
| `workout_timer_completions_v3` | `timer_complete` | `workout_timer_completions_v3_silent` |

*   All six are high importance. Each silent twin has `setSound(null, null)`
    and `enableVibration(false)`.
*   The service deletes `workout_timer_prepare` and
    `workout_timer_completions_v2` when it creates the channels, as it already
    deletes `workout_timer_completions`.
*   The ongoing countdown channel (low importance, no sound) is unchanged; a
    foreground service needs it.

**Posting the background notifications.**

*   **Android.**
    *   `TimerForegroundService` keeps ticking every second, as today. It works
        out the thresholds from `deadlineAtMillis`. When it crosses 10 s (only
        when the schedule has a `getReadyText`), 3 s or 0, it posts that cue's
        notification unless `MainActivity.isStarted` is true and in-app cues
        are active.
    *   Each threshold is passed once per schedule. A threshold already at or
        behind the remaining time when a schedule starts is marked passed, so
        the first tick never posts a stale cue. A ±15 s cancels the schedule
        and posts a new one.
    *   The get-ready notification has its own id,
        `getReadyNotificationId(timerId)`, times out after 10 s, and is
        cancelled with the others on Stop.
*   **iOS.**
    *   `scheduleTimer` adds a third request, `getReadyIdentifier(timerId)`
        (`"getReady:\(timerId)"`, like `prepareIdentifier`), at the deadline
        minus 10 s when the schedule has a `getReadyText`.
    *   A getReady or prepare request whose fire time is less than 0.5 s away
        is not added.
    *   `willPresent` returns, for a timer notification: on iOS 14 and later,
        `[]` when in-app cues are active, else `[.banner, .sound]`; on iOS 13
        (the deployment target), `[]` or `[.alert, .sound]`. Protocol
        reminders are unchanged.

**Rest timer sounds off.** On Android 8 and later a notification's sound and
vibration come from its channel, and the per-notification `setSound(null)` and
`setVibrate(null)` the service calls today are ignored, so a sounds-off rest
still rings. With this change the service posts to a channel's silent twin
when sounds are off. In the app, `canPlay` is false, so `play` is not called.
The strip's visual changes show either way.

**Notification text.** The schedule carries finished, localized strings from
Dart, since native code cannot read the ARB file. They are a record,
`RestNotificationTexts`:

```text
({String title, String countdownLabel, String body,
  String? getReadyText, String prepareText})
```

*   `title`: "Rest timer"; `countdownLabel`: "Rest" (the ongoing countdown);
    `body`: "Rest over".
*   `getReadyText`: "Get ready · Deadlift · Set 4", or null when the rest is
    15 s or shorter. Null means no get-ready cue on either platform.
*   `prepareText`: "Deadlift · Set 4 in 0:03".

The texts are computed once, when the rest is scheduled, and the schedule is
never sent again for a label change. (Sending it again would start a new
schedule, which could post a threshold the lifter already heard.)
Notifications always name the exercise, because they are read away from the
screen. In "*Exercise* · Set *k*":

*   *Exercise* is the exercise the screen shows after Log set: the next group
    member when Log set moves to it, otherwise the same exercise.
*   *k* is that exercise's Performed Set count after this Log set, plus one.
*   If that exercise has no Planned Set left and Plan-Guided Logging's
    `nextExerciseWithPlan` returns another exercise, that exercise is named
    instead, with its own Performed Set count plus one.

### 5. Finish summary

`_finishWorkout` keeps its order: read the divergence summary, then finish.
Instead of popping to Today and showing a SnackBar and then a dialog, it opens
`FinishSummarySheet` (a modal bottom sheet) over the Workout screen. It pops
the Workout screen when the sheet closes, however it closes, which returns to
the screen that opened the Workout.

*   **Layout.** The sheet is `isScrollControlled: true` with a maximum height
    of 90% of the screen. Its body is a `SingleChildScrollView` inside a
    `SafeArea`, so at 2× text it scrolls instead of overflowing.

*   **Data.** The sheet watches `workoutSummaryProvider(workoutId)`, the
    provider the Workout screen reads its `HomeWorkoutSummary` from, so it sees
    the finished `endedAt`. It shows:
    *   the Workout's title, as the Workout screen shows it;
    *   the duration, from `HomeWorkoutSummary.duration`, in the format the
        Today card uses;
    *   "*p* of *q* sets", from `performedSetCount` and `setCount`;
    *   the number of active Workout Exercises.
*   **New Bests.** The sheet watches the existing
    `progressNewBestsBetweenProvider((day, day))` and keeps the entries whose
    `workoutId` is this Workout. `day` is the Workout's `localDate`, or its
    `startedAt` in local time when that is null, as the Workout screen's
    `_workoutLocalDate` works it out today; that function becomes shared. It
    is the read the Progress Overview uses, so nothing new is computed.
    *   Each row is the New bests card's row, extracted into a shared widget,
        `NewBestRow`, so it reads the same ("Deadlift · heaviest 140 kg") with
        the Trophy Gold marker, and a tap still opens Exercise Overview.
    *   Exercise names come from the summary's `workoutExercises`
        (`exerciseId` to name), and units from `settingsControllerProvider`.
        The sheet hides the row's date, since every row is from this
        Workout.
    *   That read covers each exercise's whole history, so it can take a
        moment. The section always shows its header and one 48 dp row, which
        holds "—" until the read returns and "None" if there are none. The
        sheet doesn't jump.
*   **`Update "Lower B"`.** It shows only when the Workout is linked to a
    template and has diverged.
    *   **The lines under it.** One line per change from the existing
        `TemplateDivergenceResult`, in this order:
        *   "Add Dips" for each added exercise, in Workout order;
        *   "Remove Hip Thrust" for each removed one, in template order (a
            removed exercise has no place in the Workout);
        *   "Deadlift: sets changed" for each changed one, in Workout order;
        *   "Exercise groups changed" if groups changed, the existing
            `templateUpdateGroupsChangedNote`.
    *   **Tapping it** runs the existing `updateTemplateFromWorkout` and
        ignores further taps while it runs. The row then reads `"Lower B"
        updated` and is disabled.
    *   **On failure** it reads `Couldn't update "Lower B"` and stays enabled.
        Failure is either a `null` result (the template is gone) or an
        exception.
    *   **The menu's dialog.** The same lines replace the "+ / − / ~" text in
        the dialog that the Workout menu's "Update template" still uses. With
        no lines, the dialog keeps its "No changes to update" text
        (`templateUpdateNoChangesNote`).
*   **Copy summary.** The Workout screen's `_shareWorkoutSummary` already
    calls `HomeController.shareWorkout` and puts the text on the clipboard. It
    becomes a shared top-level `copyWorkoutSummary(HomeController controller,
    String workoutId)`, called by the Workout menu's Share and by the sheet,
    each showing its own feedback. The sheet shows "Copied" on the row for
    2 seconds. The row is labelled Copy because it does not open a share
    sheet.
*   **Done** uses the save button style.

### Invariants, agent surface, validation

*   **Set save confirms within one frame:** kept. The confirmation outranks
    every rest phase ([part 2](#2-the-status-row)).
*   **Local writes never block on the network:** nothing here touches the
    network.
*   **Derived values are never stored:** rest phases, Rest over and New Bests
    are computed on read. No column is added.
*   **No behavioural analytics:** no events are recorded.
*   **Agent surface:** none. Cues and messages are device behaviour, and
    `TemplateDivergenceResult`, which the agent contract and the golden vectors
    (`packages/golden-vectors/vectors/m34-plan-divergence.json`) cover, is not
    changed. The contract diff is empty.
*   **Validation and analytics:** no rule changes and no golden vector changes.
*   **CONTEXT.md:** no new terms. "Get ready" and "Rest over" are interface
    copy, not domain terms.

## Risks and Mitigations

| Risk | Mitigation |
| :--- | :--- |
| A cue is lost or played twice at the instant the app goes to the background or comes back, because Dart and native read the lifecycle separately | Both sides use the same meaning of visible ([part 4](#4-cues-and-notifications)), and a Dart cue more than 1 s late is skipped. The window is the length of one lifecycle transition. Accepted; the next cue in the rest still plays. |
| A cue is lost just after a route change: `setInAppTimerCues` is sent from the next tick, so native can hold the old value for up to 1 s | Accepted. The window is at most 1 s, and the next cue in the rest still plays. |
| The first cue is silent because the tones are still loading | `prepareCues` runs when a strip first mounts, well before any cue is due (the shortest getReady is 5 s after a rest starts). |
| The vibration is not felt: iOS with System Haptics off, or an Android phone with a weak motor | The tone and the strip change still carry the cue. Android uses the vibrator directly, not view haptics, so the touch-feedback setting does not suppress it. |
| Android 15 and later lower the volume of quick successive notification alerts from one app (notification cooldown), so the 0:03 and 0:00 background alerts may be quieter after the 0:10 one | Manual check on an Android 15 or later emulator ([Verification Plan](#verification-plan)). If it is too quiet, the get-ready channel can drop to default importance in a follow-up. |
| Audio focus is denied (for example during a call) | The cue still plays at its volume, and the vibration and strip change are unaffected. |
| Notification permission is off | In-app cues work. The existing "Background timer alerts are off" message shows once per app run in the strip's row, never over a confirmation with Undo ([part 2](#2-the-status-row)). |
| An updated install plays the wrong tone on a channel created by an older version | The sounded channels get new ids with sounds addressed by name, and the old channels are deleted ([part 4](#4-cues-and-notifications)). A manual step installs over 0.2.0 and checks each tone. |
| The New Bests read is slow on a long history | The section keeps a fixed-height row with "—" until the read returns ([part 5](#5-finish-summary)). |
| Finish is tapped by accident | The sheet's Done and the swipe-down both leave the Workout finished. Resume on the Workout screen reopens it, as today. |

## Alternatives Considered

### Alternative A: Keep SnackBars on the Training Screen, placed above the pinned area

*   **Pros**: Smallest change. One mechanism for every screen. The measured
    inset from part 2 already does the placement.
*   **Cons**: The SnackBar still covers the bottom of the scrolling form (the
    Comment field, Rest after) for 4 seconds after every set. Its position
    moves with the pinned area's height, so Undo is never in the same place
    twice.
*   **Reason for Rejection**: It moves the message rather than getting it off
    the form. The measured inset stays, but only for SnackBars from other
    screens.

### Alternative B: A short message under the app bar

*   **Pros**: Never near the form fields being typed into.
*   **Cons**: Undo sits at the top of a tall phone, out of reach for a
    one-handed thumb. It covers the set list, which is where the user checks
    that the set landed.
*   **Reason for Rejection**: Breaks the one-handed reach rule in AGENTS.md.

### Alternative C: A separate confirmation row above the rest strip

*   **Pros**: The strip stays untouched, and the message and the countdown can
    show together.
*   **Cons**: Either the row is always there, taking 48 dp of form height
    permanently, or it appears and disappears and makes the form jump on every
    Log set.
*   **Reason for Rejection**: Both costs land on the screen the user is typing
    into. Sharing the strip's row adds no height at normal text sizes and never
    moves the form.

### Alternative D: Put the strip and buttons in `Scaffold.bottomNavigationBar`

*   **Pros**: Flutter would place floating SnackBars above them, with no
    measuring.
*   **Cons**: A `bottomNavigationBar` stays under the keyboard. Today the
    pinned block is in the body, so it rides above the keyboard while the user
    types; moving it would hide Log set behind the keyboard.
*   **Reason for Rejection**: Costs the logging path to simplify a rare case
    (a SnackBar from another screen).

### Alternative E: A ScaffoldMessenger of the Training Screen's own

*   **Pros**: SnackBars are tied to the route by Flutter itself, with no
    `route` parameter.
*   **Cons**: The Workout screen's "Replaced · Undo" would no longer follow the
    user onto the Training Screen, which Plan-Guided Logging specifies. It does
    nothing about messages covering the form.
*   **Reason for Rejection**: Solves only the message lifetime, which #101
    already solves, and breaks a specified behaviour.

### Alternative F: Detect cues from the frames the strip draws, and store each cue's firing

*   **Pros**: Close to today's code, which detects the 3-2-1 and end cues in
    `build` and stores `prepareAlertFiredAt` and `alertFiredAt`.
*   **Cons**:
    *   No frames are drawn in the background, so the first frame after resume
        sees a jump to Rest over and would replay the end cue.
    *   A 1-second ticker started when the strip mounted puts the cues up to a
        second away from the digits.
    *   Storing a get-ready firing needs a Drift schema version and a
        migration.
*   **Reason for Rejection**: Scheduling from the deadline fixes the timing and
    the replay, and needs no new column.

### Alternative G: Play the tones with a Dart audio plugin

*   **Pros**: One Dart implementation instead of Kotlin and Swift.
*   **Cons**: A new dependency (`just_audio` or `audioplayers`) for three short
    files. The tones would be duplicated as Flutter assets next to the native
    copies the notifications need. Audio focus and the iOS audio session still
    need per-platform handling behind the plugin.
*   **Reason for Rejection**: The native channel and the tone files already
    exist, so `playCue` adds one method on each side.

### Alternative H: Keep the notifications in the foreground, but silent

*   **Pros**: No coordination between the app and the native side.
*   **Cons**: The heads-up and the banner still drop over the app bar, which
    is one of the problems. A silent notification is no cue at all for a
    phone on a bench.
*   **Reason for Rejection**: Keeps the visual problem and removes the audible
    cue.

### Alternative I: One notification per second for 3-2-1 in the background

*   **Pros**: Each beep would come from its own notification at its own
    second.
*   **Cons**: Android rate-limits alerting notifications from one app and
    collapses rapid heads-ups. iOS schedules each one as a separate pending
    request. Three notifications in the shade for one rest.
*   **Reason for Rejection**: One notification at 0:03, whose tone has three
    blips a second apart, gives the same beeps with one entry.

### Alternative J: A light SnackBar in the light theme

*   **Pros**: Matches the light theme's surfaces.
*   **Cons**: Signal Cyan on white is about 2.4:1 and fails AA for the action
    label. It would need a new, darker cyan token used only here.
*   **Reason for Rejection**: A new colour token for one component, against a
    dark bar whose colours already pass AA in both themes.

### Alternative K: A Finish summary screen, or a highlight on Today

*   **Pros**: A full screen has room for more. A highlight on Today needs no new
    surface.
*   **Cons**: A pushed screen adds a back-stack step between Finish and the
    screen the user came from. A highlight on Today has nowhere to put the
    template update except a dialog again.
*   **Reason for Rejection**: A sheet keeps the Workout visible behind it,
    holds the update in place of the dialog, and closing it has one meaning.

--------------------------------------------------------------------------------

## Non-Functional Requirements

*   **Performance.** Log set's confirmation stays within one frame
    (`setSaveConfirmationFrameBudget`), including when a rest phase is
    showing. The strip already rebuilds once a second, and the phase function
    is constant time. Tones are prepared once per app run, when a strip first
    mounts.
*   **Battery.** No new background work on Android: the foreground service
    already ticks every second during a rest. iOS adds one pending
    notification per rest.
*   **Privacy.** Nothing is recorded or sent. Cues are local.
*   **Accessibility.**
    *   Every cue pairs sound with a visible change and a vibration, and
        colour never carries a phase alone.
    *   The confirmation is a live region, and each phase change is announced
        once.
    *   Reduce Motion removes the crossfade.
    *   At large text sizes the row wraps to two lines.
*   **Rollout.** No schema, sync or contract change. Each pull request leaves
    the app working; they merge in order, and each can be reverted together
    with the ones after it. The tone files are regenerated in the same pull
    request as the code that plays them.

## Future Improvements

*   **A real share sheet** at Finish (`share_plus` or the platform share
    APIs), so the summary can go straight to a message or note. Today the
    summary is copied to the clipboard; this spec labels that action Copy.
*   **An interval timer**, if one is built, can use `TimerCuePlayer` and the
    same phases.
*   **Undo for `Update "Lower B"`** at Finish. `updateTemplateFromWorkout`
    already returns a batch id. Left out until it is needed.

--------------------------------------------------------------------------------

## Detailed Implementation Plan

Four pull requests, each against `main`, merged in order after
[#101](https://github.com/perennia-fit/perennia/pull/101). Each adds its
`CHANGELOG.md` line under `[Unreleased]`. The last one sets this spec's Status
to Current and its SITEMAP row.

### PR 1: one message style

**Verification Plan items:** the Gate, and from Accessibility the AA contrast
group for the `notice` colours.

#### `DESIGN.md` (Modify)

*   **Type / Scope**: design system.
*   **Proposed Changes**: Add the `notice` component to the YAML front matter:
    `backgroundColor: "{colors.chrome-dark}"`, `borderColor:
    "{colors.divider-dark}"`, `textColor: "{colors.text-primary-dark}"`,
    `actionColor: "{colors.primary}"`, `typography: "{typography.body}"`,
    `rounded: "{rounded.md}"`, `inset: "{spacing.base}"`. Add a prose
    paragraph: messages are a dark bar in both themes and float above the
    screen's bottom bar or buttons; the Training Screen shows its own messages
    in the rest strip's row.

#### `apps/mobile/DESIGN.md` (Modify)

*   **Type / Scope**: the app's token copy, which the token generator and the
    token test read.
*   **Proposed Changes**: The same `notice` component. Its existing differences
    from the root file are out of scope.
    `apps/mobile/tool/generate_design_tokens.dart` reads only named
    components, so `design_tokens.g.dart` does not change.

#### `apps/mobile/lib/theme/app_theme.dart` (Modify)

*   **Type / Scope**: theme.
*   **Proposed Changes**: Both themes set `snackBarTheme` from one private
    builder:
    *   `behavior: SnackBarBehavior.floating`;
    *   `backgroundColor: DesignTokens.chromeDark`;
    *   `contentTextStyle`: `AppTextStyles` body in
        `DesignTokens.textPrimaryDark`;
    *   `actionTextColor: DesignTokens.primary`;
    *   `shape: RoundedRectangleBorder(borderRadius: AppRadii.cardMd, side:
        BorderSide(color: DesignTokens.dividerDark))`;
    *   `insetPadding: EdgeInsets.all(AppDimens.base)`;
    *   `elevation: 0`.

#### `apps/mobile/test/theme/design_tokens_test.dart` (Modify)

*   **Type / Scope**: unit test.
*   **Proposed Changes**: Parse `components.notice` and assert that
    `AppTheme.light()` and `AppTheme.dark()` use its colours, radius, inset and
    elevation 0. Add `text-primary-dark` on `chrome-dark` and `primary` on
    `chrome-dark` to the WCAG AA group (4.5:1).

#### `apps/mobile/test/features/settings/settings_screen_test.dart` (Modify)

*   **Type / Scope**: widget test.
*   **Proposed Changes**: In `purge actions are explicit and separate from
    disconnect`, dismiss the "Garmin GPS purged" SnackBar after asserting it.
    The floating bar sits higher than the old fixed one and would otherwise
    cover the Purge All button the test taps next.

#### `apps/mobile/lib/features/training/widgets/replace_exercise.dart` (Modify)

*   **Type / Scope**: widget helper.
*   **Proposed Changes**: `showTrainingSnackBar` drops its `behavior` line,
    since the theme makes every SnackBar floating. The `margin` parameter stays
    until PR 2 removes it.

#### `apps/mobile/lib/features/nutrition/widgets/log_portion_screen.dart` (Modify)

*   **Type / Scope**: screen.
*   **Proposed Changes**: Remove its two `behavior: SnackBarBehavior.floating`
    lines, which the theme now sets.

### PR 2: the status row

**Verification Plan items:** the Gate; from Accessibility, `textScaler: 2.0`
for the status row and the live region on the confirmation only; the
Performance budget with no rest and with a rest running; manual check 1.

#### `apps/mobile/lib/features/training/widgets/training_confirmation.dart` (Create)

*   **Type / Scope**: value type.
*   **Proposed Changes**:
    *   `TrainingConfirmation({required String message, Key? textKey, String?
        undoLabel, VoidCallback? onUndo, bool replacesCurrent = false})`, with
        `duration` 4 s when `onUndo` is set, else 2 s.
    *   `replacesCurrent: true` keeps the current sequence number. Log set uses
        it for its Undo version.
    *   `typedef ShowTrainingConfirmation = void Function(TrainingConfirmation)`.

#### `apps/mobile/lib/features/training/widgets/rest_strip.dart` (Modify)

*   **Type / Scope**: widget.
*   **Proposed Changes**:
    *   **New parameters:** `({TrainingConfirmation confirmation, int
        sequence})? confirmation`, `ShowTrainingConfirmation onConfirmation`,
        `bool Function() undoShowing` and `ValueChanged<VoidCallback>
        whenUndoEnds`.
    *   **What it draws.** When `confirmation` is set, the strip draws it in
        place of the running or idle content, with no icon:
        *   the message in `label` style, wrapping to at most two lines, with
            `textKey` on its `Text`;
        *   Undo as a `TextButton` with a 48 dp minimum.
    *   **Semantics.** Only the message `Text` is wrapped in
        `Semantics(liveRegion: true)`.
    *   **The swap.** An `AnimatedSwitcher` keyed by `sequence` crossfades in
        150 ms, with a zero duration when `MediaQuery.disableAnimations` is set.
        During a crossfade both children are mounted, each under its own
        `sequence` key. `textKey` sits on the `Text` inside each child, so two
        children that both carry `saveSetConfirmationKey` (two Log sets in a
        row) never hold it as siblings.
    *   **Taps after Undo.** When a message with Undo ends (the `sequence` it
        held is no longer shown), `didUpdateWidget` wraps the current child in
        `IgnorePointer` for `kDoubleTapTimeout`, on a `Timer` rather than the
        crossfade's status, since Reduce Motion gives the crossfade no length.
    *   **Background alerts message.** `notifyIfBackgroundAlertsDenied(status,
        {required String message, required ShowTrainingConfirmation show,
        required bool Function() undoShowing, required
        ValueChanged<VoidCallback> whenUndoEnds})` takes these instead of a
        `BuildContext`, and shows `message` ("Background timer alerts are off")
        through `show`:
        *   a static `_backgroundAlertsNoticeShown` flag makes it show once per
            app run. It is set when the message shows, not when it is
            requested, so a screen closed during the wait does not use up the
            one showing;
        *   while `undoShowing()` is true, it passes its show step to
            `whenUndoEnds` and shows when the confirmation with Undo ends (the
            screen calls a pending callback from its clear timer).
    *   **Callers.** Both callers pass the screen's functions: the strip's
        `_start`, through its new parameters, with
        `context.l10n.trainingBackgroundAlertsDenied` after its mounted check,
        and the screen's `_startRestAfterLog`.

#### `apps/mobile/lib/features/training/widgets/training_screen.dart` (Modify)

*   **Type / Scope**: screen.
*   **Proposed Changes**:
    *   **State.** `TrainingConfirmation? _confirmation`, `int
        _confirmationSequence`, `Timer? _confirmationTimer` and `VoidCallback?
        _afterUndoEnds` (one slot; a later request replaces it, and `dispose`
        does not run it).
    *   **`_showConfirmation(c)`:**
        *   returns at once when `!mounted` (it can run after an await that
            outlives the screen);
        *   increments the sequence unless `c.replacesCurrent`;
        *   sets `_confirmation` in `setState`, with `onUndo` wrapped so that
            tapping Undo clears `_confirmation` first, then calls the
            original;
        *   restarts `_confirmationTimer` for `c.duration`; when it fires, it
            clears `_confirmation` and shows any pending background-alerts
            message.
    *   `dispose` cancels the timer.
    *   **Messages.** `_showSnackBar` becomes `_showConfirmation` at every call
        site in [part 2](#2-the-status-row). On `alreadyLogged`,
        `messenger.removeCurrentSnackBar()` becomes clearing `_confirmation`.
    *   **Log set.** Its first confirmation passes `textKey:
        TrainingScreen.saveSetConfirmationKey`. The Undo version passes the
        same key and `replacesCurrent: true`.
    *   **Undo helpers.** `_undoBatch` and `_undoLogSet` take
        `ShowTrainingConfirmation` instead of a messenger.
    *   **`_startRestAfterLog`** passes `_showConfirmation`,
        `() => _logInFlight || _confirmation?.onUndo != null` and a function
        that sets `_afterUndoEnds` to `notifyIfBackgroundAlertsDenied`.
        `_logInFlight` counts because Log set's first message has no Undo yet:
        a schedule result that arrives then, such as Start rest's, would show
        the notice only for the Undo version to overwrite it at once.
    *   **Replace.** `_replaceOpenExercise` passes `_showConfirmation` to
        `replaceExercise`.
    *   **The strip** gets `confirmation`, `onConfirmation`, and the same
        `undoShowing` and `whenUndoEnds` functions.
    *   **SnackBars from other screens.**
        *   The four children of the outer `Column` that make up the pinned
            block (`SizedBox(dense)`, `RestStrip`, `SizedBox(dense)` and the
            actions) move into one `Column`, wrapped in a private
            `_SizeReporter`.
        *   `_SizeReporter` is a `SingleChildRenderObjectWidget`. After each
            `performLayout`, its render box schedules a post-frame callback
            that writes its height to the screen's `ValueNotifier<double>
            _pinnedHeight`, if it changed.
        *   A `ValueListenableBuilder` on `_pinnedHeight` wraps the `Scaffold`
            in `Theme(data: theme.copyWith(snackBarTheme:
            theme.snackBarTheme.copyWith(insetPadding: EdgeInsets.fromLTRB(
            base, base, base, base + pinnedHeight))))`.
        *   `dispose` disposes `_pinnedHeight`.
    *   **Removed.** `_snackBarMargin` is deleted.

#### `apps/mobile/lib/features/training/widgets/replace_exercise.dart` (Modify)

*   **Type / Scope**: widget helper.
*   **Proposed Changes**:
    *   **`replaceExercise`** replaces `snackBarMargin` with a required
        `ShowTrainingConfirmation show`. It builds its three
        `TrainingConfirmation`s and calls `show`: "Already in this workout",
        "Exercise not replaced", and "Replaced" with Undo.
    *   **`undoTrainingBatch`** takes `ShowTrainingConfirmation show` in place
        of messenger, `margin` and `route`.
    *   **`showTrainingSnackBar`** keeps `route` and drops `margin`. It stays
        the Workout screen's way to show a confirmation as a SnackBar.

#### `apps/mobile/lib/features/home/widgets/workout_screen.dart` (Modify)

*   **Type / Scope**: screen.
*   **Proposed Changes**: The card's Replace passes `(c) =>
    showTrainingSnackBar(messenger, c.message, route: route, undoLabel:
    c.undoLabel, onUndo: c.onUndo)`. `messenger` and `route` are read before
    the await.

#### `docs/designs/plan-guided-logging.md` (Modify)

*   **Type / Scope**: spec.
*   **Proposed Changes**: In the Log set steps and the Replace section, where
    it says "the confirmation", add one sentence: on the Training Screen it
    shows in the rest strip's row, linking to this spec. No behaviour in that
    spec changes.

#### `apps/mobile/test/features/training/training_screen_test.dart` (Modify)

*   **Type / Scope**: widget tests.
*   **Proposed Changes**:
    *   **Existing tests.** Expectations that found a confirmation in a
        SnackBar now look inside `TrainingScreen.restStripKey`. #101's two
        tests now assert that the row clears after 4 s, and that a popped
        screen takes its message with it.
    *   **New tests:**
        *   Log set shows "Set 1 logged" with Undo inside the strip, and the
            strip's rect does not intersect the Comment field's rect.
        *   After 4 s the strip shows the rest countdown.
        *   Undo clears the message at once, reverts the Set and cancels the
            rest.
        *   Log set during a running rest shows the confirmation, not the
            rest.
        *   At `textScaler: 2.0` the message wraps and Undo is at least
            48 × 48.
        *   With `disableAnimations` the swap has no transition.
        *   Log set's message and its Undo version keep one switcher child, so
            no duplicate-key error is raised.
        *   With notification permission denied (a fake scheduler returning
            `denied`), two Log sets in a row each show "Set *n* logged" with
            Undo; "Background timer alerts are off" shows once, after the
            first Undo window ends.
        *   A confirmation requested after the screen is popped raises no
            error.
        *   A SnackBar shown by another screen floats with its bottom at or
            above the strip's top.

#### `apps/mobile/test/features/training/replace_exercise_test.dart` and `apps/mobile/test/features/home/workout_screen_replace_test.dart` (Modify)

*   **Type / Scope**: widget tests.
*   **Proposed Changes**:
    *   `replace_exercise_test.dart`: its harness calls `replaceExercise`
        directly, so it passes a recording `show` function and asserts the
        `TrainingConfirmation`s it receives (message, Undo label) instead of
        finding SnackBars.
    *   Replace from the Training Screen shows its results in the strip.
    *   Replace from the Workout screen still shows a SnackBar, and its Undo
        still switches an open Training Screen back.

#### `apps/mobile/test/performance/performance_budgets_test.dart` (Modify)

*   **Type / Scope**: performance test.
*   **Proposed Changes**:
    *   The existing case still finds `saveSetConfirmationKey` after one frame.
    *   Add a case that seeds a running rest row with 60 s left through
        `RestTimerRepository` before pumping the screen. It taps Log set and
        expects the key after one frame. (PR 3 adds the countdown
        case.)

### PR 3: rest phases, cues and notifications

**Verification Plan items:** the Gate; Kill-and-reopen mid-workout; from
Accessibility, the phase announcements; the Performance budget in countdown;
manual checks 2 to 7; the before-release checks.

Its `CHANGELOG.md` lines are an `Added` line for the get-ready cue, the in-app
tones and Rest over, and a `Fixed` line: "Rest timer sounds off now silences
rest timer notifications on Android 8 and later."

#### `apps/mobile/pubspec.yaml` (Modify)

*   **Type / Scope**: dependencies.
*   **Proposed Changes**: Add `clock` as a direct dependency, at the version
    already in `pubspec.lock` (it is there as a transitive dependency today).

#### `apps/mobile/lib/features/training/services/rest_cues.dart` (Create)

*   **Type / Scope**: pure Dart.
*   **Proposed Changes**:
    *   `enum TimerCue { getReady, countdown, tick, end }`.
    *   `sealed class RestPhase`, with `RestIdle`, `RestResting(remaining)`,
        `RestGetReady(remaining)`, `RestCountdown(remaining)` and
        `RestOver(elapsed)`.
    *   `RestPhase restPhaseAt(RestTimerRecord? timer, ({String id, DateTime
        performedAt})? newestPerformed, DateTime now)`, by the rule in
        [part 3](#3-rest-phases).
    *   `List<({Duration before, TimerCue cue})> cueScheduleFor(Duration
        duration)` returns the offsets in [part
        4](#4-cues-and-notifications), without getReady when `duration` is
        not longer than `getReadyAfterRest`.
    *   `Duration ceilToSeconds(Duration d)`, used for the strip's digits.
    *   The constants:
        *   `getReadyLead = 10 s`;
        *   `getReadyAfterRest = 15 s` (rests longer than this get the cue);
        *   `countdownLead = RestTimerRepository.prepareCueLead` (3 s);
        *   `restOverLimit = 5 min`;
        *   `cueArmLimit = 1 s` (a cue at most this far in the past is still
            armed);
        *   `cueLateLimit = 1 s` (a cue that fires at most this late still
            plays).

#### `apps/mobile/lib/features/training/services/rest_cue_scheduler.dart` (Create)

*   **Type / Scope**: pure Dart, no Flutter widgets.
*   **Proposed Changes**:
    *   `RestCueScheduler({required bool Function() canPlay, required void
        Function(TimerCue cue) onCue})`.
    *   `void update(RestTimerRecord? timer)`:
        *   when `timer` is null or not `running`, cancels every armed `Timer`
            and forgets the armed pair;
        *   when `(timer.id, timer.deadlineAt)` equals the armed pair, does
            nothing;
        *   otherwise cancels the armed `Timer`s, stores the new pair, and
            arms one `Timer` per entry of `cueScheduleFor(timer.duration)`
            whose time (`deadlineAt − before`) is at most `cueArmLimit` before
            `clock.now()`. A cue whose time has already passed (but within the
            limit) is armed with a zero delay.
    *   When an armed `Timer` fires: if `clock.now()` is at most
        `cueLateLimit` after the cue's time and `canPlay()` is true, call
        `onCue(cue)`.
    *   `void dispose()` cancels everything.
    *   Every reading of the time goes through `clock.now()`.

#### `apps/mobile/lib/features/training/services/rest_cue_owner.dart` (Create)

*   **Type / Scope**: Riverpod provider.
*   **Proposed Changes**:
    *   `restCueOwnerProvider`, a `Provider<RestCueOwner>` kept alive for the
        app's life, reading `timerBackgroundSchedulerProvider`.
    *   `RestCueOwner.report(Object strip, {required bool current})` stores
        the entry; `remove(Object strip)` drops it.
    *   After each change it computes `active = any entry is true`. When that
        differs from the last value sent, it calls
        `TimerBackgroundScheduler.setInAppTimerCues(active)`. The first value
        sent after the app starts is always sent.

#### `apps/mobile/lib/features/training/services/timer_cue_player.dart` (Create)

*   **Type / Scope**: service.
*   **Proposed Changes**: `timerCuePlayerProvider` and `abstract interface
    class TimerCuePlayer { Future<void> prepare(); Future<void> play(TimerCue
    cue, {required double volume}); }`.
    `MethodChannelTimerCuePlayer` calls `prepareCues` and `playCue` on
    `perennia/timer_background` and ignores `MissingPluginException`.

#### `apps/mobile/lib/features/training/services/timer_background_scheduler.dart` (Modify)

*   **Type / Scope**: service.
*   **Proposed Changes**:
    *   **`RestNotificationTexts`,** the record type in [part
        4](#4-cues-and-notifications), is declared here.
    *   **In-app cues.** `TimerBackgroundScheduler` gains `Future<void>
        setInAppTimerCues(bool active)`, which invokes `setInAppTimerCues
        {active}` and ignores `MissingPluginException`, as `cancel` does.
    *   **`TimerBackgroundSchedule`** gains `getReadyText` (`String?`) and
        `prepareText` (`String`), both in the platform map. A null
        `getReadyText` is sent as absent.
    *   **`TimerBackgroundSchedule.rest`** takes a `RestNotificationTexts`
        from its caller instead of hard-coding English.

#### `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

*   **Type / Scope**: repository.
*   **Proposed Changes**: Remove `RestTimerRepository.markPrepareAlertFired`,
    which has no caller after this pull request. `adjust` keeps clearing
    `prepareAlertFiredAt`. The column stays, so the Drift schema does not
    change.

#### `apps/mobile/lib/features/training/widgets/rest_strip.dart` (Modify)

*   **Type / Scope**: widget.
*   **Proposed Changes**:
    *   **Removed:** `RestTimerAlert`, `SystemRestTimerAlert`,
        `restTimerAlertProvider`, `_queueAlert`, `_queuePrepareAlert` and the
        `prepareAlertFiredAt` checks.
    *   **New parameters:**
        *   `({String id, DateTime performedAt})? newestPerformed`;
        *   `RestNotificationTexts notificationTexts`, which the screen builds.
    *   **On mount**, when `enableTicker` (the existing switch that tests turn
        off), the strip:
        *   calls `TimerCuePlayer.prepare()`, once per app run (a static
            flag);
        *   reads the first visible value from
            `WidgetsBinding.instance.lifecycleState` and keeps it current with
            an `AppLifecycleListener` (visible: anything but `paused` or
            `hidden`);
        *   creates a `RestCueScheduler` whose `canPlay` is visible, and
            `ModalRoute.of(context)?.isCurrent ?? false`, and Rest timer sounds
            on, and whose `onCue` calls `TimerCuePlayer.play(cue, volume:
            timer.alertVolume)`.
        *   In `dispose`, it disposes the scheduler and calls
            `RestCueOwner.remove(this)`.
    *   **On each timer row and each tick:**
        *   `scheduler.update(timer)`;
        *   `RestCueOwner.report(this, current: <route is current>)`;
        *   while visible, a row with status `running` at or past its
            deadline: write `markAlertFired` and cancel the background
            schedule, once per row id ([part 3](#3-rest-phases)).
    *   **On resume** (the listener's state becomes visible), the same check
        runs at once.
    *   **Ticker.** The first tick fires at the next whole second of
        `remaining`, then every second.
    *   **Drawing.** Draw `restPhaseAt(...)` by the table in [part
        3](#3-rest-phases), with `ceilToSeconds(remaining)` for the digits.
        On a phase change into getReady or over, call
        `SemanticsService.sendAnnouncement(View.of(context), text,
        Directionality.of(context))`.
    *   **Scheduling.** `_start` and `_scheduleBackground` pass
        `notificationTexts`.

#### `apps/mobile/lib/features/training/widgets/training_screen.dart` (Modify)

*   **Type / Scope**: screen.
*   **Proposed Changes**:
    *   **Notification texts.** Build `RestNotificationTexts` as in [part
        4](#4-cues-and-notifications). In Log set they are built for the
        exercise the screen will show (the next group member when it moves),
        from the Performed Set count after this Log set, before
        `_startRestAfterLog`. `getReadyText` is null when the rest is not
        longer than `getReadyAfterRest`.
    *   **`_startRestAfterLog`** passes the texts to
        `TimerBackgroundSchedule.rest`. The strip gets the same texts for
        `_start` (a rest started from the strip, for the open exercise).
    *   **Strip inputs.** Pass the strip `newestPerformed`: the Workout's
        Performed Set with the latest `performedAt`, from the Sets stream the
        screen already watches.
    *   No rescheduling when the open exercise or row changes.

#### `apps/mobile/lib/l10n/app_en.arb` and the generated `app_localizations*.dart` (Modify)

*   **Type / Scope**: strings.
*   **Proposed Changes**: Add the keys below, with placeholder types in their
    `@` entries (`int` for `number`, `String` for the others), then run
    `flutter gen-l10n` and commit the generated files.
    *   `trainingRestGetReady`: "Get ready · {time}"
    *   `trainingRestOver`: "Rest over"
    *   `trainingRestOverElapsed`: "+{time}"
    *   `trainingRestNotificationTitle`: "Rest timer"
    *   `trainingRestNotificationCountdown`: "Rest"
    *   `trainingRestNotificationGetReady`: "Get ready · {exercise} · Set
        {number}"
    *   `trainingRestNotificationPrepare`: "{exercise} · Set {number} in
        {time}"
    *   `trainingRestNotificationOver`: "Rest over"

#### `apps/mobile/android/app/src/main/AndroidManifest.xml` (Modify)

*   **Type / Scope**: Android manifest.
*   **Proposed Changes**: Add `<uses-permission
    android:name="android.permission.VIBRATE" />`.

#### `apps/mobile/android/app/src/main/kotlin/fit/perennia/app/MainActivity.kt` (Modify)

*   **Type / Scope**: Android channel.
*   **Proposed Changes**:
    *   **Visible flag.** A companion `@Volatile var isStarted = false`, set
        true in `onStart` and false in `onStop`.
    *   **In-app cues flag.** `configureFlutterEngine` sets
        `TimerForegroundService.inAppCuesActive = false` before it registers
        the channel.
    *   **New channel methods:**
        *   `prepareCues` prepares a lazily built `TimerCueSounds`;
        *   `playCue {cue, volume}` plays it;
        *   `setInAppTimerCues {active}` sets
            `TimerForegroundService.inAppCuesActive`.
    *   **`cleanUpFlutterEngine`** (overridden) releases `TimerCueSounds`.
    *   **`scheduleTimer`** passes `getReadyText` and `prepareText` to the
        service's intent.

#### `apps/mobile/android/app/src/main/kotlin/fit/perennia/app/TimerCueSounds.kt` (Create)

*   **Type / Scope**: Android audio and vibration.
*   **Proposed Changes**:
    *   **Players.** Three `MediaPlayer`s (`get_ready`, `prepare_beep`,
        `timer_complete`) with `AudioAttributes(USAGE_MEDIA,
        CONTENT_TYPE_SONIFICATION)`, prepared in `prepare()` and released in
        `release()`.
    *   **`play(cue, volume)`:**
        *   for a cue with a tone: request
            `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` (an `AudioFocusRequest` on
            API 26 and later, `requestAudioFocus(listener, STREAM_MUSIC,
            AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)` below), set the volume, seek
            to 0 and start, and abandon focus in `OnCompletionListener`;
        *   `tick` requests no focus and plays no tone;
        *   every cue runs its vibration from the table in [part
            4](#4-cues-and-notifications).
    *   **Vibrator.** API 31 and later:
        `VibratorManager.defaultVibrator`. API 26–30: `Vibrator` with
        `VibrationEffect.createWaveform`. Below 26: `vibrate(LongArray, -1)`.

#### `apps/mobile/android/app/src/main/kotlin/fit/perennia/app/TimerForegroundService.kt` (Modify)

*   **Type / Scope**: Android service.
*   **Proposed Changes**:
    *   **Shared flag.** A companion `@Volatile var inAppCuesActive = false`.
    *   **Extras.** `EXTRA_GET_READY_TEXT` and `EXTRA_PREPARE_TEXT`, parsed in
        `intentFrom` and `onStartCommand` next to the existing extras.
    *   **Thresholds.** Per schedule, `getReadyPassed`, `preparePassed` and
        `endPassed`:
        *   at schedule start, each starts true when the remaining time is
            already at or below its threshold (10 s, 3 s, 0), or, for
            get-ready, when there is no `getReadyText`;
        *   on each tick, a threshold not yet passed that the remaining time
            reaches is marked passed, and its notification is posted unless
            `MainActivity.isStarted && inAppCuesActive`;
        *   at 0 the service stops either way.
    *   **Channels.** The three sounded channels and their silent twins from
        [part 4](#4-cues-and-notifications), with
        `rawSoundUri(name: String)` building
        `android.resource://<pkg>/raw/<name>`. `createChannels` deletes
        `workout_timer_prepare` and `workout_timer_completions_v2`, as it
        deletes `LEGACY_COMPLETION_CHANNEL_ID` today.
    *   **Sounds off.** When `soundEnabled` is false, each notification uses
        its channel's silent twin. The per-notification mute calls stay for
        API below 26.
    *   **Get ready.** `buildGetReadyNotification()` with `getReadyText` and a
        10 s timeout, posted under `getReadyNotificationId(timerId) =
        notificationId("getReady:$timerId")`. `ACTION_CANCEL` cancels it with
        the others.
    *   **Text.** The prepare notification uses `prepareText`.

#### `apps/mobile/android/app/src/main/res/values/strings.xml` (Modify)

*   **Type / Scope**: Android strings.
*   **Proposed Changes**: Names and descriptions of the new channels:
    *   get ready: "Rest get-ready alert" / "Plays 10 seconds before a rest
        ends";
    *   the prepare and completion channels keep their existing wording;
    *   each silent twin: the same name with " (silent)" appended.

#### `apps/mobile/android/app/src/main/res/raw/get_ready.ogg` (Create) and `prepare_beep.ogg` (Modify)

*   **Type / Scope**: generated audio.
*   **Proposed Changes**: Output of `node tools/gen-timer-sounds.mjs`. No
    `.wav` file is left in `res/raw`.

#### `apps/mobile/ios/Runner/AppDelegate.swift` (Modify)

*   **Type / Scope**: iOS channel and notifications.
*   **Proposed Changes**:
    *   **In-app cues flag.** `private var inAppCuesActive = false`, set to
        false in `didInitializeImplicitFlutterEngine` before the timer channel
        is registered.
    *   **New channel methods:** `prepareCues` and `playCue` go through
        `TimerCueSounds`; `setInAppTimerCues {active}` sets the flag.
    *   **`scheduleTimer`:**
        *   adds the `getReadyIdentifier(timerId)` request
            (`"getReady:\(timerId)"`) at the deadline minus 10 s, with
            `GetReady.caf` and `getReadyText`, when `getReadyText` is present;
        *   the prepare request uses `prepareText`;
        *   a getReady or prepare request whose fire time is less than 0.5 s
            away is not added (today's `max(1.0, …)` is removed for both).
    *   **`cancelTimer`** removes the get-ready identifier with the others.
    *   **`willPresent`,** for a timer notification: iOS 14 and later, `[]`
        when `inAppCuesActive`, else `[.banner, .sound]`; iOS 13, `[]` or
        `[.alert, .sound]`. The `#available` branch stays. Protocol reminders
        are unchanged.

#### `apps/mobile/ios/Runner/TimerCueSounds.swift` (Create)

*   **Type / Scope**: iOS audio and haptics.
*   **Proposed Changes**:
    *   **Players.** Three `AVAudioPlayer`s, prepared in `prepare()`.
    *   **`play(cue, volume)`:**
        *   for a cue with a tone: set the `AVAudioSession` category to
            `.playback` with `[.mixWithOthers, .duckOthers]`, activate it,
            and play at `volume`; deactivate with
            `.notifyOthersOnDeactivation` in `audioPlayerDidFinishPlaying`;
        *   every cue fires its `UIImpactFeedbackGenerator` pattern from the
            table in [part 4](#4-cues-and-notifications).

#### `apps/mobile/ios/Runner/Sounds/GetReady.caf` (Create), `PrepareBeep.caf` (Modify), `apps/mobile/ios/Runner/Sounds/timer_sounds.LICENSE.md` (Modify) and `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (Modify)

*   **Type / Scope**: generated audio, licence note and project file.
*   **Proposed Changes**:
    *   The `.caf` files are the script's output.
    *   The licence note names `GetReady.caf` and the new 3-2-1 timing.
    *   `project.pbxproj` adds `TimerCueSounds.swift` to the Runner target's
        sources and `GetReady.caf` to its resources.

#### `tools/gen-timer-sounds.mjs` and `apps/mobile/android/app/src/main/timer_sounds.LICENSE.md` (Modify)

*   **Type / Scope**: tooling and licence note.
*   **Proposed Changes**:
    *   **`PREPARE`** becomes a 90 ms tone, 910 ms of silence, a 90 ms tone,
        910 ms of silence and a 90 ms tone, all at 1200 Hz with gain 0.6.
    *   **New `GET_READY` cue:** a 120 ms tone, 120 ms of silence and a
        120 ms tone, all at 660 Hz with gain 0.35, written as `get_ready` and
        `GetReady`.
    *   **Clean-up.** The script deletes each Android `.wav` after
        transcoding it to `.ogg`.
    *   **The header comment** lists the three cues and their timing.
    *   **The licence note** names the new files and the new timing.

#### `DESIGN.md` and `apps/mobile/DESIGN.md` (Modify)

*   **Type / Scope**: design system.
*   **Proposed Changes**: In the root file, extend the Rest strip paragraph;
    in `apps/mobile/DESIGN.md`, which has none, add the same paragraph:
    *   Resting shows the elapsed bar; Get ready and 3-2-1 show a 2 dp
        `primary` border with no fill; Rest over uses `surface`.
    *   "The strip's elapsed bar and its Get-ready border count as one cyan
        element, separate from the Current row's highlight; no other part of
        the strip is cyan."

#### `apps/mobile/lib/features/settings/widgets/logging_settings_screen.dart` (Modify)

*   **Type / Scope**: settings copy.
*   **Proposed Changes**: The switch titled "Timer sounds & vibration" gets
    the subtitle "Off silences rest timer tones and vibration". Both stay
    hard-coded English like the title; moving them to the ARB file is out of
    scope.

#### Tests

*   **`apps/mobile/test/features/training/rest_cues_test.dart` (Create):**
    *   `restPhaseAt` at every boundary, for 16 s, 15 s and 3 s rests;
    *   `expired` at the deadline reads as over;
    *   over goes idle at 5 min + 1 s, and when a later Set was performed;
    *   `canceled` reads as idle;
    *   `cueScheduleFor` with and without getReady;
    *   `ceilToSeconds` at 2.999 s, 3.0 s and 3.001 s.
*   **`apps/mobile/test/features/training/rest_cue_scheduler_test.dart`
    (Create),** under `fakeAsync`, with a recording `onCue`:
    *   a 20 s rest: getReady at −10 s, countdown at −3 s, ticks at −2 s and
        −1 s, end at 0, in that order;
    *   no getReady for a 15 s rest;
    *   `canPlay` false: no cue reaches `onCue`;
    *   `update` with a deadline moved to now (−15 s to zero): end still
        plays;
    *   `update` at 0:05 left: countdown, ticks and end, but no getReady;
    *   a cue that fires 1.5 s late (the clock jumped) does not play;
    *   a new deadline cancels the old cues; `update(null)` and `dispose`
        cancel all.
*   **`apps/mobile/test/features/training/rest_cue_owner_test.dart`
    (Create):** with a fake scheduler, two strips reporting: `active` is
    sent once on the first `true`, not again while either is current, and
    `false` when both are not current or removed.
*   **`apps/mobile/test/features/training/training_screen_test.dart`
    (Modify):**
    *   **Replaced:** the `restTimerAlert` pump parameter and the
        `_RecordingRestTimerAlert` fake become `timerCuePlayer` and a
        recording `TimerCuePlayer`. The three tests that use them are
        rewritten for the new rules. The expired-timer test now expects no
        cue and one `markAlertFired`.
    *   **New, with the ticker enabled and fake `TimerCuePlayer` and
        `TimerBackgroundScheduler`, using `tester.pump` with durations:**
        *   CUJ 3's strip texts at 0:10, 0:03 and 0:00, and the cue order
            (the timing itself is covered by the scheduler test);
        *   the digits read "0:03" when the countdown cue plays;
        *   sounds off plays nothing and still changes the strip;
        *   with the lifecycle at `paused`, no cue plays;
        *   with a second route pushed over the Training Screen, no cue plays,
            and `setInAppTimerCues(false)` is sent;
        *   kill-and-reopen at 0:05 plays countdown, ticks and end, but no
            getReady;
        *   reopen after 0:00 shows "Rest over" with the right elapsed time,
            plays no cue, and writes `markAlertFired` once;
        *   Log set with Rest after Off during Rest over returns the strip to
            idle after the confirmation;
        *   after a superset Log set, the scheduled texts name the next group
            member and its next Set number; opening another exercise sends no
            new schedule.
*   **`apps/mobile/test/features/training/timer_background_scheduler_test.dart`
    (Modify):** the platform map carries `getReadyText` and `prepareText`, has
    no `getReadyText` key when it is null, and `setInAppTimerCues` invokes the
    method and swallows `MissingPluginException`.
*   **`apps/mobile/test/data/training_repositories_test.dart` (Modify):**
    remove the `markPrepareAlertFired` test.
*   **Protocol test fakes (Modify):**
    `apps/mobile/test/features/protocols/protocol_reminder_scheduler_test.dart`,
    `protocol_reminder_tap_test.dart` and `protocols_day_view_test.dart`
    implement `TimerBackgroundScheduler`; each fake gains
    `setInAppTimerCues` as a no-op.
*   **`apps/mobile/test/performance/performance_budgets_test.dart`
    (Modify):** add a case that seeds a running rest row with 2 s left, which
    puts the strip in countdown, taps Log set and expects
    `saveSetConfirmationKey` after one frame.
*   **Native:** no unit test harness exists for `TimerForegroundService`,
    `TimerCueSounds` or `AppDelegate`. They are checked by hand
    ([Verification Plan](#verification-plan)).

### PR 4: Finish summary

**Verification Plan items:** the Gate; Repositories against in-memory SQLite;
from Accessibility, `textScaler: 2.0` for the sheet; manual checks 8 and 9.

#### `apps/mobile/lib/features/home/widgets/workout_duration.dart` (Create)

*   **Type / Scope**: formatting.
*   **Proposed Changes**:
    *   `String formatWorkoutDuration(AppLocalizations l10n, Duration?
        duration)` moves here from the two identical private copies in
        `home_screen.dart` and `workout_screen.dart`. Both call it.
    *   `TrainingDayDate workoutLocalDate(HomeWorkoutSummary workout)` moves
        here from `workout_screen.dart`'s private `_workoutLocalDate`. The
        Workout screen and the sheet call it.

#### `apps/mobile/lib/features/home/widgets/copy_workout_summary.dart` (Create)

*   **Type / Scope**: helper.
*   **Proposed Changes**: `Future<void> copyWorkoutSummary(HomeController
    controller, String workoutId)` calls `controller.shareWorkout(workoutId)`
    and puts the text on the clipboard with `Clipboard.setData`. It shows
    nothing; each caller shows its own feedback.

#### `apps/mobile/lib/features/progress/widgets/new_best_row.dart` (Create) and `new_bests_card.dart` (Modify)

*   **Type / Scope**: widget.
*   **Proposed Changes**:
    *   The private `_Row` in `new_bests_card.dart` becomes the public
        `NewBestRow({required ProgressNewBestRow row, required UnitSystem
        unitSystem, TrainingDayDate? today})`, with no visual change. The card
        uses it and passes `today` as it does now.
    *   `today == null` hides the row's date.
    *   The tap to Exercise Overview stays.

#### `apps/mobile/lib/features/template_divergence/widgets/template_divergence_diff_text.dart` (Modify)

*   **Type / Scope**: formatting.
*   **Proposed Changes**:
    *   `templateDivergenceLines(TemplateDivergenceResult result,
        AppLocalizations l10n) → List<String>`, with the four line kinds in
        the order of [part 5](#5-finish-summary). The groups line is
        `l10n.templateUpdateGroupsChangedNote`.
    *   `templateDivergenceDiffText` joins them with new lines, so the dialog
        uses the same words. With no lines it returns
        `l10n.templateUpdateNoChangesNote`, as today.
    *   No change to `apps/mobile/lib/domain`.

#### `apps/mobile/lib/features/home/widgets/finish_summary_sheet.dart` (Create)

*   **Type / Scope**: widget.
*   **Proposed Changes**:
    *   **Entry point:** `Future<void> showFinishSummarySheet(BuildContext
        context, {required String workoutId, required
        TemplateDivergenceSummary? divergenceSummary})`.
    *   **Presentation.** `showModalBottomSheet` with `isScrollControlled:
        true` and `BoxConstraints(maxHeight: 0.9 × screen height)`; the body
        is a `SingleChildScrollView` inside a `SafeArea`.
    *   **`FinishSummarySheet`** is a `ConsumerStatefulWidget`. It watches
        `workoutSummaryProvider(workoutId)` and
        `progressNewBestsBetweenProvider((day, day))`, with `day =
        workoutLocalDate(summary)`, keeps the rows whose `workoutId` is this
        Workout, and shows the parts in [part 5](#5-finish-summary).
        *   Each row is a `NewBestRow` with `today: null`, the exercise name
            from the summary's `workoutExercises`, and `unitSystem` from
            `settingsControllerProvider`.
    *   **Update** calls
        `templateDivergenceFeatureRepositoryProvider.updateTemplateFromWorkout`.
        A `null` result or an exception shows the failure text.
    *   **Copy summary** calls `copyWorkoutSummary` with the `HomeController` that
        `homeControllerProvider` gives and `workoutId`, then shows "Copied".
    *   **Keys:** `sheetKey`, `updateTemplateKey`, `copySummaryKey`, `doneKey`.

#### `apps/mobile/lib/features/home/widgets/workout_screen.dart` (Modify)

*   **Type / Scope**: screen.
*   **Proposed Changes**:
    *   **Finish.** `_finishWorkout` finishes, awaits
        `showFinishSummarySheet`, then pops the Workout screen.
    *   **Removed:** the "Workout finished · Share" SnackBar, the Finish call
        to `_offerTemplateUpdate`, and `finishedSnackBarShareActionKey`.
    *   **Share.** The menu's Share calls `copyWorkoutSummary`, then shows
        `homeWorkoutSummaryCopied` as a SnackBar. `_shareWorkoutSummary` is
        deleted.
    *   **The menu's "Update template"** keeps the dialog.

#### `apps/mobile/lib/l10n/app_en.arb` (Modify)

*   **Type / Scope**: strings.
*   **Proposed Changes**:
    *   **Sheet copy:**
        *   `finishSummaryFacts`: "{duration} · {sets} · {exercises, plural,
            =1{1 exercise} other{{exercises} exercises}}", where `sets` is the
            existing `workoutPerformedSetsOfTotal` ("{performed} of {total}
            sets") and `exercises` is an `int`
        *   `finishSummaryNewBests`: "New bests"
        *   `finishSummaryNoNewBests`: "None"
        *   `finishSummaryUpdate`: `Update "{template}"`
        *   `finishSummaryUpdated`: `"{template}" updated`
        *   `finishSummaryUpdateFailed`: `Couldn't update "{template}"`
        *   `finishSummaryCopy`: "Copy summary"
        *   `finishSummaryCopied`: "Copied"
        *   `finishSummaryDone`: "Done"
    *   **Change lines:**
        *   `templateChangeAdd`: "Add {exercise}"
        *   `templateChangeRemove`: "Remove {exercise}"
        *   `templateChangeSets`: "{exercise}: sets changed"
        *   (The groups line reuses `templateUpdateGroupsChangedNote`.)
    *   **Placeholder types** in the `@` entries: `int` for counts, `String`
        for the others. Run `flutter gen-l10n` and commit the generated
        `app_localizations*.dart`.
    *   **Removed:** `workoutFinished` and `workoutShareAction`, used only by
        the removed SnackBar.

#### `docs/designs/plan-guided-logging.md` (Modify)

*   **Type / Scope**: spec.
*   **Proposed Changes**: The passages that describe the Finish-time prompt
    (in the Goals, the CUJ on template updates, the rest prescription notes
    and the Replace section's divergence note) now say that the Finish
    summary's Update row offers the update, linking to this spec. The
    Workout menu's **Update template** is unchanged.

#### `AGENTS.md` (Modify)

*   **Type / Scope**: docs.
*   **Proposed Changes**: In the screen map, "the Finish-time 'update the
    template?' prompt" becomes "the Finish summary's Update row".

#### `docs/designs/workout-feedback.md` and `docs/designs/SITEMAP.md` (Modify)

*   **Type / Scope**: spec.
*   **Proposed Changes**: Status Current in this spec and in its SITEMAP row.

#### Tests

*   **`apps/mobile/test/features/template_divergence/template_divergence_diff_text_test.dart`
    (Create):** every line kind, in order (removed exercises in template
    order), the dialog text, and the no-changes text.
*   **`apps/mobile/test/features/home/finish_summary_sheet_test.dart` (Create),**
    against in-memory SQLite:
    *   CUJ 5 end to end: facts, the New Bests row, the change lines;
    *   the "—" placeholder before New Bests return, and "None" when empty;
    *   Update writes the template, ignores a second tap, and disables the
        row;
    *   a failing update (a fake repository that returns `null`) shows the
        failure text and stays enabled;
    *   Copy summary puts the text on the clipboard;
    *   Done and a swipe-down both pop the Workout screen;
    *   an unlinked or undiverged Workout has no Update row;
    *   at `textScaler: 2.0` no text is clipped and the sheet scrolls.
    *   The New Bests read runs `compute`, so these tests wrap it in
        `tester.runAsync`.
*   **`apps/mobile/test/app_shell_test.dart` (Modify):** the Finish tests
    (about lines 2127–2194) expect the sheet instead of the SnackBar and the
    dialog. Their fake `HomeRepository` serves `watchWorkout` for the
    Workout, and the progress repository is overridden with an empty New
    Bests stream.
*   **Other existing Finish tests** in `apps/mobile/test/features/home/` that
    expect the SnackBar or the dialog at Finish now expect the sheet.

## Verification Plan

*   **Gate**: `node tools/ci-local.mjs mobile` for every pull request. No pull
    request changes `apps/mobile/lib/domain`, so `golden` does not run.
*   **Repositories against in-memory SQLite**: the Finish sheet's reads and
    `updateTemplateFromWorkout`.
*   **Kill-and-reopen mid-workout**: PR 3's tests reopen the
    Training Screen at 0:05 and after 0:00.
*   **Accessibility**: widget tests at `textScaler: 2.0` for the status row and
    the sheet; the AA contrast group for the `notice` colours; the live region
    on the confirmation only; the phase announcements.
*   **Performance**: `performance_budgets_test.dart` passes the Log set
    one-frame budget, with and without a rest in countdown.
*   **Manual checks, on the Android emulator (API 34 and API 35) and the iOS
    simulator.** Native audio and notifications have no test harness. Each
    step is done in the light and dark themes:
    1.  **CUJ 1 and 2.** Log a set: the row reads "Set *n* logged" with Undo,
        nothing covers the Comment field, and after 4 s the row reads
        "Rest *m*:*ss*". Log another and tap Undo: the Set returns to planned
        and the row reads "Start rest".
    2.  **CUJ 3.** A 0:20 rest with music playing in another app, the app
        open: the get-ready tone at 0:10 with the strip reading
        "Get ready · 0:10", beeps as the strip shows 0:03, 0:02 and 0:01, the
        end tone at 0:00 with "Rest over · +0:00", the music ducking and
        coming back after each tone, and no heads-up or banner.
    3.  **CUJ 4.** The same rest with the app in the background: notifications
        "Get ready · *Exercise* · Set *k*", "*Exercise* · Set *k* in 0:03" and
        "Rest over", each with its tone. Reopening after 0:00 shows
        "Rest over · +*m*:*ss*" and plays nothing.
    4.  **On Today during a rest:** the same three notifications, with sound.
    5.  **Pull down the notification shade** during a rest on the Training
        Screen: the in-app cues still play, and no notification posts.
    6.  **Rest timer sounds off:** no tones and no vibration in the app; the
        background notifications post silently on Android 8 and later; the
        strip still changes.
    7.  **Update install (Android).** Install 0.2.0, run one rest, then install
        this build over it: each background notification plays its own tone
        (get-ready, 3-2-1, end), and Settings › Notifications lists no
        `workout_timer_prepare` or `workout_timer_completions_v2` channel.
    8.  **CUJ 5.** Finish Lower B after changing it: the sheet shows the facts,
        New bests, `Update "Lower B"` with "Remove Hip Thrust" and
        "Deadlift: sets changed", Copy summary and Done. Update reads
        `"Lower B" updated`; Done returns to the screen that opened the
        Workout.
    9.  **CUJ 6.** Copy a Workout summary from the Workout menu: "Workout
        summary copied" shows as a dark bar above the bottom bar and closes
        after 2 s.
*   **Before release, on an Android 15 or later phone and an iPhone:** music
    in earbuds ducks under each tone and comes back; with the phone face-up on
    a bench, each vibration is felt; with the app in the background, the 0:03
    and 0:00 notifications are still audible after the 0:10 one (Android 15's
    notification cooldown).
*   **Not covered by automated tests**: whether audio ducks on a real device,
    how strong the vibration feels, Android 15's notification cooldown, and
    the channel migration on an update install. The steps above cover them by
    hand.
