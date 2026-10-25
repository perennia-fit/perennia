# Protocol Schedules and Reminders

*   **Author:** Leonardo Pinheiro
*   **Status:** Draft
*   **Date:** 2026-10-25

--------------------------------------------------------------------------------

## Overview

Perennia's Protocols domain lets a user record what they take: supplements,
vitamins, hormones, peptides, medications. A **Compound** is an item in the
user's own library. A **Dose** is one logged administration of it. A
**Protocol** is a named course of one or more Compounds, each with an optional
**Schedule** saying what the user intends to take. These terms are defined in
[CONTEXT.md](../../CONTEXT.md); this spec changes the definition of Schedule and
adds new terms, listed under Goals.

Today a Schedule is only an amount, a unit, a route, and one of six coarse
frequencies (once, twice or three times daily, every other day, weekly, as
needed). It has no time of day. The app never reminds the user of anything, and
it cannot show how closely the user follows the plan they wrote.

This spec makes the Schedule precise enough to plan against: when each dose is
due, on which days, and over what period. It then adds the three things that a
precise plan makes possible:

1.  **Reminders** at the planned times.
2.  **A planned-versus-logged list for the day**, where the user logs what is
    due in one or two taps.
3.  **A consistency view** for each Compound: what was taken, when, and how much,
    plotted against what was planned.

All three are computed from the plan and the logged Doses. None of them stores a
result. The same computation runs in the app (Dart) and on the server for agents
(TypeScript), pinned together by shared test vectors, the way validation already
is ([ARCHITECTURE.md](../../ARCHITECTURE.md), "Validation").

### The neutral-instrument rule

This domain covers substances that some users take against medical guidance,
and some that are illegal where the user lives. Perennia records what the user
does. It never promotes, advises or judges. The existing rules, which this spec
keeps and extends, are:

*   The app never categorizes a Compound by what it is or whether it is legal.
    It ships only a few over-the-counter examples (creatine, vitamin D,
    caffeine, magnesium, melatonin, fish oil).
*   No dosing advice, no sourcing, and no claims that anything works. The Effect
    view carries a "For personal tracking; not medical advice." notice, and
    nothing in the app moralizes.
*   The section can be locked behind a PIN or biometrics, and hidden at a
    glance.
*   Protocols data is excluded from CSV export. It is included in the encrypted
    portable archive, so the user always keeps a complete backup.
*   Protocols data syncs like all other data, and the user's own agent has the
    same access the app has.

This spec adds one more: **the plan belongs to the user, and the app only
mirrors it back.** Reminders fire because the user asked for them. Consistency
describes what happened against a plan the user wrote. Nothing is scored,
streaked, rewarded or marked as failed.

## The Problem

The users this is for are longevity-focused hybrid athletes. They follow several
protocols at once, each with its own rhythm. A real example from one user:

| Compound | Plan |
| :------- | :--- |
| TRT | Every day, morning |
| AgeMate, MNEM | Every day, on waking |
| Creatine | Every day, before training |
| GHK-Cu | Every day around 21:00, two months on and one month off |
| BPC-157 | Every evening, only for the length of an injury course |

Across the wider audience the patterns also include weekly injections on a set
weekday (GLP-1 medications) and doses taken several times a day.

Two things go wrong today:

1.  **Doses are forgotten.** Nothing reminds the user. The cues they rely on
    instead (waking up, leaving for the gym, the last meal) are unreliable; the
    example user regularly forgets GHK-Cu and AgeMate. A reminder tied to
    starting a Workout was considered and rejected: by the time a Workout starts
    in the app, the user has already left the house.
2.  **The user can't see whether they are following their plan.** They want to
    understand how what they take affects their health, and the existing
    **Effect** view compares their Metrics and performance before, during and
    after a Protocol. But it can't distinguish a month of taking a compound
    every day at 09:00 from a month of taking it four days a week at random
    times. Without that, the Effect view can mislead.

The existing Schedule can't fix either problem. With no time of day there is
nothing to remind at. With frequencies like "twice daily" or "weekly", which
have no times, no weekday and no starting day, the app can't work out which
days a dose was due. So it can't show what was missed. On/off cycles and courses
with an end can't be described at all, beyond a single start and end date on
the Protocol.

## Goals

1.  **A Schedule describes when doses are due.** The user can say:
    *   **at what times:** one or more clock times a day, or a count per day with
        no fixed time;
    *   **on which days:** every day, chosen weekdays, or every N days;
    *   **over what period:** ongoing; until an end date (with a helper that
        turns "20 doses" into an end date); or a repeating on/off cycle such as
        60 days on and 30 off.

    The user can also pause a Protocol and end it early. This is part of the
    plan, not a record against a dose.
2.  **One reminder per planned time.** All items due at the same minute share
    one notification. Its text never names a Compound, and tapping it opens the
    app through the lock to that day's planned list. Reminders are off until the
    user turns them on for a Protocol.
3.  **A planned-versus-logged list for the day,** inside the locked Protocol Day
    view. Logging one planned dose takes at most two taps, and logging
    everything due takes one action. This keeps the repeat-in-two-taps rule
    already used for training sets ([AGENTS.md](../../AGENTS.md), "UX rules of
    thumb").
4.  **A consistency view for each Compound** over a chosen date range. Each day
    gets one status from a closed set, and the view shows the actual times and
    amounts next to the planned ones. It returns statuses and counts only:
    never a percentage, a score or a streak.
5.  **Agents get the same answers.** The new Schedule shape can be read and
    written through the agent API in the same release as the app. The planned
    day and consistency come to the agent API in a later stage of the same
    feature. One shared definition, in Dart and TypeScript, produces every
    answer, pinned by golden vectors that both test suites run.
6.  **Existing data survives.** Every existing Schedule keeps reading
    correctly. No clock time is invented for a Schedule that never had one, and
    reminders stay off for migrated Schedules.
7.  **The vocabulary is defined.** [CONTEXT.md](../../CONTEXT.md) gains entries
    for the new terms, and the Schedule entry is rewritten in the same pull
    request as the code.

## Non-Goals

*   **Behavioral or habit protocols** (mobility, light exposure, cold
    exposure). Protocols are for substances. A mobility session is a Workout,
    and its plan belongs to Training's Routines.
*   **Reminders tied to events** such as starting a Workout. They fire too late
    to be useful.
*   **Dose titration**, meaning a dose that steps up over time (common with
    GLP-1 medications).
*   **Follow-up reminders, snooze and a daily catch-up notification.** v1
    reminds once per planned time.
*   **Logging from the notification itself.** v1 notifications open the app.
*   **"Fixed number of doses" as a way for a Protocol to end.** It survives only
    as a helper that sets an end date.
*   **A per-dose "skip today" record.** A dose that wasn't logged appears as
    "not logged".
*   **CSV export of Protocols data.** The exclusion stays as it is.
*   **Server push** to cancel reminders on other devices.
*   **Any stored result:** no stored day statuses, gaps or reminder history.
    Nothing records that a reminder fired, was tapped or was dismissed.

The deferred items, with what each one needs before it can be built, are listed
under Future Improvements.

## Prerequisites (separate pull requests)

These fix problems that exist today, independent of this feature. Each lands as
its own bug-fix pull request before this feature's implementation begins.

| # | Fix | Done when |
| :- | :-- | :-------- |
| P1 | Agent Schedule writes are validated against the app's registries. | The agent API rejects a Schedule whose frequency, unit or route is outside the app's registries, or whose amount is missing. Golden vectors in `packages/golden-vectors` cover it, and both languages run them. |
| P2 | Sync pull skips entity types it doesn't recognize. | A pull containing an unknown entity type skips that row, saves the pull cursor, and continues; a test proves it. |
| P3 | The Effect window agrees across languages. | The Effect window fixture lives in `packages/golden-vectors`, both suites run it, and Dart and TypeScript pass the same cases. |
| P4 | CI runs every Protocols golden vector. | A pull request that changes only `packages/golden-vectors/**` runs both the Dart and TypeScript suites. `tools/ci-local.mjs` mirrors the change in the same commit. |
| P5 | The docs describe how Protocols data syncs. | [ARCHITECTURE.md](../../ARCHITECTURE.md) no longer says the Protocols payload is opaque to the server. The server does read it, which is what gives the user's agent full access. |

## Open Questions

None open. The five questions carried in from the brief (Schedule history, the
time model, the sync cutover, where the period lives, and the notification
stack) are answered in the Technical Plan, decisions D1 to D5.

## Critical User Journeys (CUJs)

### CUJ 1: Morning stack, one reminder

*   **Given**: An active Protocol "Daily" with reminders on, holding TRT
    (09:00) and AgeMate (09:00). Nothing is logged today.
*   **When**: It is 09:00, and later the user taps the notification.
*   **Then**: One notification arrives, reading "Planned for 9:00 AM". It names
    no Compound. Tapping it opens the locked Supplements section (after the PIN
    or biometric prompt, if the lock is on) on today's Protocol Day. The Planned
    list shows TRT and AgeMate as "Not yet". One tap on "Log all planned"
    records both Doses at the planned amounts, timed now. Both rows then read
    "Logged".

### CUJ 2: A dose logged before its reminder

*   **Given**: The CUJ 1 setup. The user logs TRT at 08:40 from the Planned
    list, but not AgeMate.
*   **When**: It is 09:00.
*   **Then**: The 09:00 notification still fires, because AgeMate is still due.
    If both had been logged before 09:00, it would not fire on this device.

### CUJ 3: Off-cycle days

*   **Given**: A Protocol "Skin" holding GHK-Cu at 21:00 daily, with a cycle of
    60 days on and 30 days off, anchored on 2026-09-01.
*   **When**: The date is 2026-11-05, day 66 of the 90-day cycle.
*   **Then**: No reminder fires and the Planned list doesn't show GHK-Cu. In the
    consistency view the day reads "Off cycle", not "Not logged". On 2026-11-30,
    the first day of the next on-period, the 21:00 reminder starts again.

### CUJ 4: A course that ends

*   **Given**: The user creates a Protocol "Shoulder" for BPC-157 at 21:00
    daily, and uses the helper to turn "20 doses, starting today (2026-10-26)"
    into an end date. The helper sets 2026-11-14.
*   **When**: The date passes 2026-11-14.
*   **Then**: No more reminders, and the Protocol shows as ended. Doses logged
    on that course keep their Protocol tag and still show in its Effect view.

### CUJ 5: Pausing after a reaction

*   **Given**: "Skin" is in an on-period. The user pauses it from 2026-10-10 to
    2026-10-16.
*   **When**: Those dates arrive, and later the user opens the consistency
    view.
*   **Then**: No reminders fire during the pause. Those seven days read
    "Paused", not "Not logged". The cycle doesn't shift: day 0 is still
    2026-09-01.

### CUJ 6: Editing a plan mid-course

*   **Given**: TRT has been planned at 09:00 since 2026-09-01. On 2026-10-20 the
    user moves it to 07:00.
*   **When**: The user opens TRT's consistency view.
*   **Then**: Days before 2026-10-20 are compared against 09:00. Days from
    2026-10-20 are compared against 07:00. From 2026-10-20 the reminder fires at
    07:00, including that day if 07:00 hasn't passed yet.

### CUJ 7: A dose logged late, for last night

*   **Given**: GHK-Cu is planned at 21:00. The user took it at 21:05 but logs it
    at 00:30.
*   **When**: The user opens the log sheet from the Planned list for yesterday's
    date.
*   **Then**: The time defaults to 21:00 on yesterday's date, because the user
    started from yesterday's planned row, and it can be changed. Saving records
    the Dose on yesterday's Protocol Day, and yesterday reads "Logged". Had the
    user started from today's quick log instead, the picker's date field would
    let them set yesterday.

### CUJ 8: Travel

*   **Given**: TRT is planned at 09:00. The user flies from São Paulo to Lisbon.
*   **When**: The phone's timezone changes.
*   **Then**: Reminders move to 09:00 Lisbon time. Doses already logged keep
    their own local date and time as recorded. Grouping past days never
    changes.

### CUJ 9: A second device, or an agent, logs first

*   **Given**: The user has two signed-in phones, both with reminders on. At
    08:55 their agent logs TRT through the API.
*   **When**: It is 09:00 and the second phone hasn't synced since 08:00.
*   **Then**: The second phone's reminder may still fire for TRT. On opening it
    syncs, and the Planned list shows TRT as "Logged". Each phone has a local
    "Reminders on this device" switch for anyone who doesn't want them twice.
    This limitation is accepted; see Future Improvements.

### CUJ 10: Notification permission denied

*   **Given**: The user turns on reminders for a Protocol and declines the
    system's notification permission.
*   **When**: The user returns to the Protocol screen.
*   **Then**: The reminders switch shows "Notifications are off for Perennia",
    with a button to the system settings. The Planned list and consistency view
    work as usual.

### CUJ 11: Not opening the app for weeks

*   **Given**: Reminders are on, and the user doesn't open the app for 20 days.
*   **When**: The scheduling horizon runs out (D5).
*   **Then**: Reminders stop at the horizon. The reminder status screen in
    Settings shows "Reminders scheduled through <date>", so the stop is visible
    rather than silent. Opening the app schedules the next window.

## Technical Plan (Architecture)

### Shape of the change

```text
                 authored, synced                     derived, never stored
   ┌────────────────────────────────────┐     ┌──────────────────────────────────┐
   │ Protocol                           │     │ Protocol Plan core (pure)        │
   │   period: ongoing | until | cycle  │──┐  │   Dart: lib/domain/protocols/    │
   │   pauses, start/end local dates    │  │  │   TS:   apps/server/src/         │
   │ Schedule versions (per member)     │──┼─▶│                                  │
   │   effectiveFrom, rule: times+days  │  │  │ plannedOccurrences(range)        │
   │ Dose                               │──┘  │ dayStatuses(occurrences, doses)  │
   │   localDate, localTime (frozen)    │     └───────────┬──────────────────────┘
   └────────────────────────────────────┘                 │
                                    ┌─────────────────────┼───────────────────┐
                                    ▼                     ▼                   ▼
                          Planned list (day)     Consistency view    Reminder reconciler
                          Protocol Day view      per Compound        device only, never
                                    ▲                                  synced
                                    │            Agent REST/MCP reads (later stage)
                              golden vectors pin Dart == TS
```

Every surface asks the same core two questions: "what was planned on these
dates?" and "how did the logged Doses line up with it?". No surface reads a
Schedule directly. This copies the routine "Up next" pattern already in the
repository: a pure Dart function (`lib/domain/training/routine_up_next.dart`),
its TypeScript twin (`deriveAgentRoutineUpNext` in
`apps/server/src/agent-plan-reads.ts`), and one vector file with a JSON Schema
that both test suites run (`packages/golden-vectors/vectors/m34-routine-up-next.json`).

### D1. Schedules keep their history

Editing a Schedule never overwrites it. An edit adds a new **Schedule
Version** with an `effectiveFrom` local date set to the day of the edit. For any
date, the version that applies is the one with the latest `effectiveFrom` on or
before that date. If two versions share a date, which happens when two devices
edit offline on the same day, the one with the larger id wins. Ids are UUIDv7,
so that is the later one, and every device and the server agree.

An edit takes effect the same day (CUJ 6). Removing a Compound from a Protocol
adds a final version with an empty rule rather than archiving the history, so
past days still compare against the plan that applied then.

This is the authored plan's own history, the same kind of data as the
Protocol's dates. It is not a stored result. The rejected option, comparing
every past day against the current plan, would make the consistency view
misdescribe the past after every edit. That defeats the reason for the view
(see The Problem).

### D2. Dates and times are local, and the core is timezone-free

*   **Protocol bounds become local dates.** `startDate` and `endDate` are stored
    as `YYYY-MM-DD` strings, with an inclusive end, the same form as
    `ProtocolDayDate`. Today they are UTC instants, which have no stable
    calendar day. Off by one at midnight in Tokyo is enough to shift a cycle.
*   **Planned times are wall-clock times,** `HH:MM`. They follow the phone
    wherever it goes (CUJ 8).
*   **Each Dose freezes its UTC offset.** A new `utcOffsetMinutes` column is set
    at log time, next to the existing `localDate`. Together with `tookAt`, it
    gives the Dose's local clock time permanently. The existing `timezone` column
    holds an abbreviation such as "BRT", which can't be converted back. It stays
    as a display label, and the agent contract's description of it is corrected
    to say so. The same abbreviation problem in Workouts and Nutrition is out of
    scope here.
*   **The shared core never sees a timezone.** It takes and returns local dates
    and `HH:MM` strings, and receives "today" as an input. The server never works
    out "today" for a user; agent reads require a date (D6). Daylight-saving and
    travel handling lives only in the device's reminder scheduler. A time that
    doesn't exist on a daylight-saving change day moves forward to the next valid
    minute, and a time that occurs twice fires once.

### D3. Hard sync cutover

The app is unreleased, so there are no clients in the field to keep working.
`SYNC_PROTOCOL_VERSION` goes from 1 to 2 in `apps/server/src/sync.ts`. The sync
request schemas already require the version as a literal, so a version-1 client
is rejected with an error instead of silently erasing fields it doesn't know.
This removes the risk of an older client overwriting a rich Schedule with its
partial image.

The new plan data lives inside the existing `protocols` and `schedules` rows,
as typed columns plus one versioned JSON value each. No new synced entity type
is added. **Stored data is never rewritten.** A legacy row stays as it is, and
every reader, Dart and TypeScript, converts it when reading it, through one
pure, vector-tested function: the **legacy upcaster**. The row takes the new
shape the next time the user edits it. A one-time server migration was
considered and rejected: the server's migration runner runs SQL only, so the
conversion rules would exist a third time, in SQL, outside the vectors. A
one-time device migration that rewrote rows would be a synced write, and
whichever device upgraded last would win.

The upcaster's rules:

| Legacy frequency | Converted rule | Reminders |
| :--------------- | :------------- | :-------- |
| onceDaily | every day, 1 untimed dose | off |
| twiceDaily | every day, 2 untimed doses | off |
| threeTimesDaily | every day, 3 untimed doses | off |
| everyOtherDay | every 2 days from the Protocol's start, 1 untimed dose | off |
| weekly | weekly on the Protocol start date's weekday, 1 untimed dose | off |
| asNeeded | as needed: no planned doses | off |

No clock time is invented. An **untimed** planned dose counts per day like any
other but has no reminder, until the user gives it a time. A legacy Protocol's
start and end instants become local dates in the reader's timezone: the
device's own zone in the app, and UTC on the server. Before 1.0 this data is
developer and generated test data, so a one-day difference on a few legacy rows
between the app and an agent read is accepted. The next edit writes local dates
and removes it.

### D4. The period lives on the Protocol; days and times live on each Schedule

A **Protocol Period** says when a whole Protocol is active:

*   **ongoing**: from the start date, no end;
*   **until**: from the start date to an end date. The "N doses" helper only
    computes this end date from the start, the rule and N; it stores nothing
    else;
*   **cycle**: N days on, M days off, repeating from an anchor date, which
    defaults to the start date. A user already three weeks into a cycle sets the
    anchor in the past. A cycle may also have an end date.

**Pauses** are date ranges on the Protocol. A paused day plans nothing and
reads "Paused". A pause does not shift a cycle; the anchor stays where it is
(CUJ 5). Ending early sets the end date to today.

A **Schedule Rule** says when, on an active day, a member Compound is due:

*   **days**: every day, chosen weekdays, or every N days from an anchor date;
*   **times**: a list of `HH:MM` times, or a count of untimed doses;
*   the planned amount, unit and route, as today;
*   or **as needed**, which plans nothing.

Putting the period on the Protocol keeps one Protocol equal to one course. That
matters for the Effect view, which compares outcomes before, during and after a
Protocol. A stack mixing a cycling Compound with ongoing ones is modeled as two
Protocols, for example "Skin" for GHK-Cu and "Daily" for the rest. A Compound
can still sit in both. Its planned doses for a day are the sum across its active
Protocols.

How a date is decided, in order: outside the Protocol's bounds → not planned;
paused → "Paused"; in a cycle's off-period → "Off cycle"; then the member's
Schedule Version for that date decides by its days and times.

### D5. Reminders are a device-local reconciler over `flutter_local_notifications`

*   **Library:** `flutter_local_notifications`, with `timezone` and
    `flutter_timezone` to schedule wall-clock times in the phone's own zone. The
    rest timer keeps its existing native channel unchanged. `AppDelegate.swift`
    becomes a router: responses whose identifier carries the timer prefix go to
    the existing timer handler, and everything else goes to the plugin. Today it
    sends every response to the timer handler.
*   **Android:** inexact delivery (`inexactAllowWhileIdle`), with no
    exact-alarm permission. A supplement reminder a few minutes late is
    acceptable, and Play policy restricts exact alarms. The plugin's boot and
    time-change receivers are registered in the manifest.
*   **One notification per planned time.** Each notification has a
    deterministic id from (local date, `HH:MM`), so re-running the reconciler
    replaces instead of duplicating. Every item due at that minute shares it.
*   **Text is always generic:** title "Supplements", body "Planned for
    9:00 AM". This holds whether or not the lock is on, so turning the lock on
    later can't leave named reminders queued. Android notifications are
    `VISIBILITY_PRIVATE`, and the channel is named "Reminders".
*   **The reconciler** works out the desired set of notifications from the core
    (D4) and diffs it against what is pending. It runs on app start and resume,
    after any Dose, Schedule or Protocol change, after sync, and on
    timezone or clock change. It drops a planned time once everything at that
    time is logged (CUJ 2).
*   **The horizon** is the next 14 days, capped at 48 pending notifications. That
    leaves 16 of iOS's 64 for the rest timer, which uses 2 per timer. When the
    cap cuts the window short, the status screen shows the real end date
    (CUJ 11).
*   **Per device:** a local "Reminders on this device" setting, default on,
    stored in the device-level `settings.json`, never synced. Reminder state
    (what is pending, what fired, what was tapped) is never synced and never
    written to the Activity Log.
*   **Permission** is requested when the user first turns reminders on for a
    Protocol, never at onboarding (CUJ 10).
*   **Tap:** the payload carries only `{kind: "protocolReminder", localDate}`.
    The app opens through `ProtocolsLockGate` to that date's Protocol Day.

### D6. Matching, statuses and the agent surface

**Matching**, for one Compound on one local date: the planned doses come from
every active Protocol containing the Compound. The logged Doses are every
non-archived Dose of that Compound with that `localDate`, whether tagged or
not. The Protocol tag records which Protocol a dose was logged under; it never
decides whether the dose counts, the same rule as Template Link in Training.
Logged Doses fill the planned times in time order. Only the counts decide the
status; times are shown, never judged.

**Day status**, one per Compound per date, from a closed set. Each has a text
label, never color alone:

| Status | Meaning |
| :----- | :------ |
| Not planned | No active plan that day (the reason is shown: outside the dates, as needed) |
| Paused | The Protocol is paused that day |
| Off cycle | In a cycle's off-period |
| Pending | Today, and not all planned doses are logged yet |
| Logged | Logged count ≥ planned count |
| Partly logged | 0 < logged < planned, on a past day |
| Not logged | Nothing logged, on a past day with doses planned |

Extra Doses beyond the plan, and Doses on a day with no plan, are shown as
"extra" next to the status. They never change it. UI copy and API fields never
use "missed", "late", "overdue", "adherence", "streak", or a percentage.

**Amounts** are compared through the existing resolved active mass when both
sides resolve. Otherwise each is shown as entered, with no comparison.

**The Planned list** sits at the top of the Protocol Day view, inside the lock.
Each row shows the Compound, the planned time (or "Any time") and amount, and
its status. Tapping a row opens the log sheet prefilled with the planned amount
and route. The time is the planned time on that row's date for a past row, and
now for today. "Log all planned" logs every pending row on that day in one
Batch. The log sheet's time picker gains a date field (CUJ 7). Prefilling the
time from the last Dose stops, because it records times that never happened.

**The consistency view** opens from a Compound or from a Protocol, which shows
its members. For a date range (default: the last 30 days), it shows a chart of
each Dose's time of day against the planned times, built with `fl_chart` like
the existing Effect timeline, and below it a day-by-day list of statuses,
times and amounts. The Effect view itself is unchanged; this spec doesn't make
Effect cycle-aware.

**The agent surface:**

*   *Same release as the app:* Protocol and Schedule reads and writes carry the
    new period, pauses, versions and rule, validated by the same shared two-tier
    module as the app (see Validation below).
*   *Later stage:* two new reads, the planned doses for a date range and the day
    statuses for a date range. Both require `fromLocalDate` and `toLocalDate`,
    at most 366 days apart, plus `today`, because the server never infers a
    user's date. They return the per-day summary by default and the per-dose
    detail on request. The MCP tools mirror them.

### Validation

Plan values join the shared two-tier validation module. They hard-reject the
impossible: a malformed time, an empty times list on a timed rule, N < 1, more
than 12 times a day, cycle on or off lengths of 0 or over 3650 days, an end
before the start, overlapping pauses. They soft-warn the improbable: more than
6 times a day, and a cycle off-period longer than its on-period. The same
vectors run in Dart and TypeScript.

## Alternatives Considered

### Alternative A: Remind when a Workout starts

*   **Pros**: Matches the cue several users rely on today ("before the gym").
    It is the one event the app can actually observe.
*   **Cons**: By the time a Workout starts in the app, the user has left the
    house without the dose. Waking, meals and bedtime can't be observed at all.
*   **Reason for Rejection**: It fires too late to prevent the forgotten dose,
    which is the problem being solved. Clock times are predictable, and the user
    can set them to match their routine.

### Alternative B: Generalize Protocols to habits and behaviors

*   **Pros**: One place for everything a user "follows": supplements, light
    exposure, mobility breaks.
*   **Cons**: A Dose is an amount, a unit and a route, so habits need a second
    kind of entry. A mobility session is already a Workout with a Routine plan.
    Protocols carry the strictest privacy rules in the app (lock, export
    exclusion), which don't suit habits. And an open-ended habit list turns the
    feature into a general habit tracker.
*   **Reason for Rejection**: It splits one activity across two domains, and it
    dilutes the substance domain's privacy posture. Protocols stay for
    substances.

### Alternative C: Log from the notification ("Log all as planned")

*   **Pros**: Logging takes one tap, without opening the app.
*   **Cons**:
    *   A double tap, a redelivered notification, a stale notification, or two
        devices each create separate Doses, which sync never merges. A
        duplicate TRT or GLP-1 Dose is a safety problem.
    *   It writes while the lock is on, about items the user can't see.
    *   It needs a second database connection in a background engine, which
        tempts a write that skips validation and the Activity Log.
    *   "At tap time" records times that never happened.
*   **Reason for Rejection**: Deferred, not dropped. v1 opens the app instead,
    where "Log all planned" is one tap. The conditions for bringing it back are
    under Future Improvements.

### Alternative D: Follow-up reminders and a daily catch-up

*   **Pros**: A missed reminder gets a second chance.
*   **Cons**: Notification content is fixed when it is scheduled, days ahead,
    so a catch-up can't list what is outstanding at noon. A Dose logged on
    another device or by an agent can't cancel it without server push, which
    Perennia doesn't have. Follow-ups multiply notifications against iOS's limit
    of 64 pending, and they risk spamming the user.
*   **Reason for Rejection**: Deferred. One reminder per planned time solves
    most of the problem, and the Planned list covers the rest whenever the user
    opens the app.

### Alternative E: Record on each Dose which planned dose it fills

*   **Pros**: Matching is exact: a Dose says "I am the 21:00 dose of
    2026-10-25". It also handles a dose taken after midnight for the previous
    night.
*   **Cons**: Every Dose and the agent API gain a field. The quick log path
    and agent writes wouldn't set it, so a fallback rule is needed anyway. Doses
    would then depend on the plan's identity, which today they deliberately
    don't: a Dose describes itself.
*   **Reason for Rejection**: Counting per Compound per local date gives the
    same answer in the cases that matter, with no new field. The late-night
    case is handled by letting the user set the true date and time (CUJ 7).

### Alternative F: A matching window, or a day boundary later than midnight

*   **Pros**: A dose at 00:30 would count for the 21:00 dose the night before,
    without the user editing anything.
*   **Cons**: It is a hidden rule. A dose taken at 00:30 would sit on a
    different day in the consistency view than in the Protocol Day view, which
    groups by the frozen local date.
*   **Reason for Rejection**: An accurate record is easier to trust than a
    clever one. The log sheet gains a date field instead.

### Alternative G: Compare every past day against the current plan

*   **Pros**: No version history, so the data model is simpler.
*   **Cons**: Every edit rewrites how the past looks. Moving TRT from 09:00 to
    07:00 would make two months of 09:00 doses look two hours off plan.
*   **Reason for Rejection**: It makes the consistency view describe the past
    wrongly, which defeats its purpose (D1).

### Alternative H: Put the period (until, cycle) on each Schedule

*   **Pros**: One Protocol can hold a cycling Compound next to ongoing ones.
*   **Cons**: A Protocol would no longer be one course, so its Effect view
    couldn't say what "during" means. A pause would have to apply per member or
    to all of them, and both are confusing.
*   **Reason for Rejection**: The cost is one extra Protocol per distinct
    rhythm, which is how users already describe them ("my skin protocol"). See
    D4.

### Alternative I: One Protocol per cycle phase

*   **Pros**: No cycle concept at all. Each on-period is a Protocol with a date
    range.
*   **Cons**: The user re-creates the Protocol every three months, and the
    reminders lapse whenever they forget to.
*   **Reason for Rejection**: It fails the GHK-Cu case that motivated the
    feature.

### Alternative J: Keep older clients working (dual-write)

*   **Pros**: Version-1 clients keep syncing.
*   **Cons**: Every write must also fill a legacy `frequency` that can't
    express the new rule. An older client editing a Schedule still erases its
    times, because it pushes the whole row.
*   **Reason for Rejection**: Nothing has shipped, so there are no older
    clients to protect. A hard version bump fails loudly instead of losing data
    silently (D3).

### Alternative K: iCalendar recurrence rules (RRULE) instead of a custom rule

*   **Pros**: A standard, with libraries in both languages. It could later
    export to a calendar.
*   **Cons**: It has no on/off cycles and no untimed doses. It is far larger
    than the handful of patterns needed, so two languages would have to agree
    on, and validate, a format mostly unused here. Library behavior differs
    across implementations, which golden vectors would then have to pin.
*   **Reason for Rejection**: The custom rule is small enough to specify and
    vector-test completely (D4).

### Alternative L: Build reminders on the rest timer's native channel

*   **Pros**: No new dependency.
*   **Cons**: Scheduling, boot and time-change handling, and timezone-aware
    triggers would each be written twice, in Swift and Kotlin, and tested
    without Flutter's test tools.
*   **Reason for Rejection**: `flutter_local_notifications` already solves
    those. The timer stays on its channel, with taps routed by identifier
    (D5). Moving the timer onto the plugin was also rejected for v1: it
    rewrites a working feature for no user benefit.

### Alternative M: Repeating OS triggers instead of a rolling window

*   **Pros**: One pending notification per daily time, instead of one per day,
    which uses far less of the 64-notification budget.
*   **Cons**: A repeating trigger can't skip off-cycle days, pauses, end dates
    or already-logged doses. Each of those would need a second mechanism.
*   **Reason for Rejection**: One mechanism, the rolling window, covers every
    rule. The cost is a 14-day horizon that the status screen makes visible.

### Alternative N: A consistency score or streak

*   **Pros**: Quick to read.
*   **Cons**: A score is a judgment, and a streak is a reward. Both push the
    user to keep taking whatever the plan holds, which breaks the
    neutral-instrument rule for substances the app must never promote.
*   **Reason for Rejection**: Statuses and counts describe what happened
    without grading it (D6).

--------------------------------------------------------------------------------

## Non-Functional Requirements

*   **Privacy.**
    *   Notification text never names a Compound, a Protocol or an amount.
    *   Notification payloads carry only a kind and a local date.
    *   The new payload keys (`period`, `pauses`, `rule`, `effective_from`,
        `utc_offset_minutes`, `reminders_enabled`) join the server's
        observability deny-list, so they never reach logs or crash reports.
    *   CSV export keeps excluding all Protocols data, including the new
        fields.
    *   Reminder state never leaves the device.
*   **No behavioral analytics.** Nothing records that a reminder fired, was
    shown, tapped or dismissed, locally or remotely. The reminder status screen
    reads the plugin's pending list live; it stores nothing.
*   **The logging path.** "Log all planned" and single logs write through the
    existing `ProtocolsRepository.logDose` path, and confirm within one frame.
    No step waits on the network.
*   **Performance.**
    *   The Planned list computes one day for the user's active Protocols.
    *   The consistency view computes at most 366 days for one Compound.
    *   The reconciler computes 14 days.
    *   All three run in memory over rows that are already read. No cost is
        expected beyond a stream rebuild, and this is checked by the existing
        performance tests in `apps/mobile/test/performance/`.
*   **Rollout and rollback.** The sync protocol bump is one-way. Rolling back
    means shipping a build that speaks protocol 2 and ignores the new fields,
    which the legacy upcaster already does in reverse: legacy fields stay
    readable. No feature flag. Reminders are off until a user turns them on for
    a Protocol, so an installed build changes nothing for a user who doesn't.

--------------------------------------------------------------------------------

### Additional Resources

*   [AGENTS.md](../../AGENTS.md): the invariants this spec preserves, and the
    UX rules (two-tap repeat logging, gym-floor ergonomics, color never the
    only signal).
*   [CONTEXT.md](../../CONTEXT.md): Compound, Dose, Protocol, Schedule,
    Protocol Day, Effect, Template Link, Activity Log, Batch.
*   [ARCHITECTURE.md](../../ARCHITECTURE.md): layering, the contract spine,
    sync, and shared two-tier validation.
*   [DESIGN.md](../../DESIGN.md): tokens and components for the Planned list,
    the editor and the consistency view.
*   The routine "Up next" pattern this core copies:
    `apps/mobile/lib/domain/training/routine_up_next.dart`,
    `apps/server/src/agent-plan-reads.ts`,
    `packages/golden-vectors/vectors/m34-routine-up-next.json`.

### Invariants this touches

| Invariant (AGENTS.md) | How it is preserved |
| :-------------------- | :------------------ |
| Derived analytics are computed, never stored or synced | Planned doses, day statuses and reminders are computed on read. Schedule Versions and Pauses are authored plan data, not results. |
| Sets (here, Doses) are self-describing | Doses gain a frozen UTC offset, and nothing about a Dose depends on a Schedule. Matching reads Doses but never writes to them. |
| User-facing delete is archive; no cascading deletes | Removing a member adds an empty-rule version. Archiving a Protocol leaves its versions and its tagged Doses untouched. |
| Restore and import are merge-only | The portable archive reader accepts format 1 and format 2. Nothing in this feature deletes on import. |
| Local writes never block on the network | Every write is local first. Reminders are scheduled on the device. |
| Sync is silent LWW with recoverable losers | Versions with the same `effectiveFrom` resolve by id, the same on every device. Edits are Activity Log entries as today. |
| One shared two-tier validation module | Schedule Rule and Protocol Period validation join it, in both languages, with vectors. |
| No behavioral analytics | No reminder telemetry of any kind (see Non-Functional Requirements). |

### Future Improvements

| Follow-up | Why it was deferred | Needs |
| :-------- | :------------------ | :---- |
| Log from the notification | Duplicates, writing while locked, a background write path (Alternative C) | Deterministic Dose ids per planned dose, so a repeat tap converges; a re-check of what is already logged; hidden while the lock is on; a write through `logDose`; evidence that opening the app is too slow |
| Daily catch-up notification | Can't stay accurate across devices (Alternative D) | Silent push to cancel it, or an accepted stale catch-up |
| Follow-up reminders and snooze | Notification budget and spam (Alternative D) | A per-day notification cap within the D5 budget |
| Remote cancellation of reminders | No push infrastructure | Silent push (FCM/APNs), with its own privacy review |
| A per-dose "skip today" record | A gap is enough for v1 | Evidence that "skipped on purpose" must look different from "not logged" |
| Dose titration | Not needed by the motivating stack | A list of dose steps on the Schedule Rule, built on Schedule Versions |
| A cycle-aware Effect view | Effect treats a cycling Protocol's off-periods as "during" | The Protocol Plan core's day states as Effect's window input, with vectors for both languages |
| Opt-in CSV export of Protocols data | Separate from reminders | A small change of its own that keeps "excluded by default" |
| Timezone offsets for Workouts and Nutrition | The same abbreviation problem, out of this scope | The `utcOffsetMinutes` approach from D2, applied to those tables |

--------------------------------------------------------------------------------

## Detailed Implementation Plan

Work lands in six phases, each its own pull request, after the prerequisites
P1 to P5. Each phase leaves the app buildable, the gate green, and the app
usable.

### Data shapes (fixed by this spec)

**`protocols` row** (Drift and sync payload):

| Field | Type | Meaning |
| :---- | :--- | :------ |
| `start_local_date` | `YYYY-MM-DD`, nullable | Null only on legacy rows; readers fall back to `start_date` |
| `end_local_date` | `YYYY-MM-DD`, nullable | Inclusive. Null = ongoing |
| `start_date`, `end_date` | instant, nullable | Legacy only. Never written by new code |
| `period` | JSON, nullable | `{"v":1,"cycle":null \| {"on_days":int,"off_days":int,"anchor":"YYYY-MM-DD"},"pauses":[{"from":"YYYY-MM-DD","to":"YYYY-MM-DD"}]}`. Null = no cycle, no pauses |
| `reminders_enabled` | bool, default false | Synced plan data: "remind me about this Protocol" |

**`schedules` row = one Schedule Version:**

| Field | Type | Meaning |
| :---- | :--- | :------ |
| `effective_from` | `YYYY-MM-DD`, nullable | Null only on legacy rows = since the Protocol's start |
| `rule` | JSON, nullable | Null only on legacy rows; readers upcast `frequency` |
| `frequency` | string, nullable | Legacy only. Never written by new code |
| `dose_amount_value`, `dose_amount_entered`, `dose_unit`, `route` | as today, now nullable | Required by validation for `timed` and `untimed` rules; null for `as_needed` and `none` |

`rule` JSON, version 1:

```text
{"v":1,"kind":"timed",   "days":DAYS,"times":["HH:MM", ...]}   1..12 distinct times, sorted
{"v":1,"kind":"untimed", "days":DAYS,"count":int}              1..12
{"v":1,"kind":"as_needed"}
{"v":1,"kind":"none"}                                          the member was removed
DAYS = {"kind":"daily"}
     | {"kind":"weekdays","weekdays":[1..7, ...]}              ISO 8601, 1 = Monday
     | {"kind":"every_n_days","n":2..365,"anchor":"YYYY-MM-DD"}
```

**`doses` row:** adds `utc_offset_minutes` (int, nullable; null only on legacy
rows).

**Version rules:**
*   An edit on a day after the current version's `effective_from` inserts a
    new version with `effective_from` = today.
*   An edit on the same day updates that day's version in place.
*   Removing a member inserts a `none` version.
*   Versions are never archived individually; archiving a Protocol archives it
    as today.

### Shared core API (pure; Dart and TypeScript mirror each other)

```text
planDays(protocols: PlanProtocol[], from: LocalDate, to: LocalDate) -> PlanDay[]
  PlanProtocol = {protocolId, startLocalDate, endLocalDate?, period?, members: [
                   {compoundId, versions: [{id, effectiveFrom?, rule, amount?, unit?, route?}]}]}
  PlanDay      = {protocolId, compoundId, localDate,
                  state: "active" | "outside" | "paused" | "off_cycle" | "as_needed",
                  planned: [{slot: int, localTime: "HH:MM" | null, amount?, unit?, route?}]}

dayStatuses(planDays: PlanDay[], doses: PlanDose[], today: LocalDate) -> DayStatus[]
  PlanDose  = {doseId, compoundId, localDate, localTime: "HH:MM", sequence: int}
  DayStatus = {compoundId, localDate,
               status: "not_planned" | "paused" | "off_cycle" | "pending" |
                       "logged" | "partly_logged" | "not_logged",
               plannedCount, loggedCount, extraCount,
               fills: [{slot, plannedLocalTime | null, doseId}]}
  Dates after `today` are not returned. A Compound in several Protocols sums
  their planned doses for the day. Its state is "active" if any Protocol is
  active. Otherwise "paused" or "off_cycle" is taken in that order, and
  otherwise "not_planned".

upcastLegacySchedule(frequency, protocolStartLocalDate) -> rule     (the D3 table)
endDateForDoseCount(startLocalDate, rule, period?, count) -> LocalDate
validateScheduleRule(rule, amount) / validateProtocolPeriod(period, start, end)
  -> {rejects: [rule], warnings: [rule]}   the two-tier shape `dose_validation` uses
```

`sequence` orders Doses that share a local time; the caller assigns it from the
UUIDv7 id. No function parses an instant or a timezone.

### Target Files to Create/Modify

#### Phase 1: the shared core and its vectors (no user-visible change)

##### 1. `packages/golden-vectors/vectors/m36-protocol-plan.json` (Create)

*   **Type / Scope**: Golden vectors.
*   **Proposed Changes**: Cases for each function above, grouped by `domain`:
    `rule_codec`, `period_codec`, `legacy_upcast`, `plan_days`,
    `day_statuses`, `dose_count_end_date`, `plan_validation`. Required cases
    include every CUJ in this spec with its dates, an every-N-days anchor
    before the range, a cycle anchor before the start, overlapping Protocols
    for one Compound, two versions on the same date (the id tie-break), a
    removed member, and extra Doses. Top-level `schemaVersion: 1`.

##### 2. `packages/golden-vectors/vectors/m36-protocol-plan.schema.json` (Create)

*   **Type / Scope**: JSON Schema.
*   **Proposed Changes**: Governs file 1, as `m34-routine-up-next.schema.json`
    does for its file. Its `schemaVersion` constant matches the Dart and TS
    runners' constants.

##### 3. `packages/golden-vectors/vectors/README.md` (Modify)

*   **Proposed Changes**: A section for m36 stating the version rule (all three
    constants move together) and that cases contain no timezones.

##### 4. `apps/mobile/lib/domain/protocols/protocol_plan.dart` (Create)

*   **Type / Scope**: Dart pure domain.
*   **Proposed Changes**: Types and JSON codecs for Schedule Rule, Protocol
    Period, Pause, Schedule Version, `PlanProtocol`, `PlanDay`, `PlanDose`,
    `DayStatus`, plus `upcastLegacySchedule`. Codecs reject unknown `kind`s
    and `v` values other than 1.

##### 5. `apps/mobile/lib/domain/protocols/protocol_plan_days.dart` (Create)

*   **Proposed Changes**: `planDays`, `dayStatuses`, `endDateForDoseCount`.
    It doesn't import `protocols.dart` registries beyond unit and route, and
    it does no I/O.

##### 6. `apps/mobile/lib/domain/protocols/protocol_plan_validation.dart` (Create)

*   **Proposed Changes**: `validateScheduleRule` and `validateProtocolPeriod`,
    with the hard rejects and soft warnings in the Validation section.

##### 7. `apps/mobile/test/domain/protocol_plan_golden_test.dart` (Create)

*   **Proposed Changes**: Runs every m36 case against files 4 to 6. It asserts
    its schema-version constant equals the file's.

##### 8. `apps/server/src/protocol-plan.ts` (Create)

*   **Type / Scope**: TypeScript twin of files 4 to 6.
*   **Proposed Changes**: The same functions, names in camelCase, the same
    JSON. No database access.

##### 9. `apps/server/test/protocol-plan.golden.test.mjs` (Create)

*   **Proposed Changes**: Runs every m36 case against file 8.

##### 10. `tools/ci-local.mjs` and `.github/workflows/ci.yml` (Modify)

*   **Proposed Changes**: Add files 7 and 9 to the `golden` job's test lists,
    and add the new source paths to its path filters. Both files change in the
    same commit.

#### Phase 2: storage, sync and the agent plan shape

##### 11. `apps/mobile/lib/data/local/app_database.dart` (Modify)

*   **Type / Scope**: Drift schema, version 57 → 58.
*   **Proposed Changes**:
    *   Rebuild `protocols` and `schedules` with Drift's `TableMigration`, to
        the shapes above. Copy every value as it is; convert nothing.
    *   Add `doses.utc_offset_minutes`.
    *   Add an index on `schedules (protocol_compound_id, effective_from)`.
    *   Foreign keys are re-checked after the rebuild, with
        `PRAGMA foreign_key_check` returning no rows.

##### 12. `apps/mobile/lib/data/local/app_database.g.dart` (Regenerate)

*   **Proposed Changes**: `build_runner` output for file 11.

##### 13. `apps/mobile/lib/domain/protocols/protocols.dart` (Modify)

*   **Proposed Changes**:
    *   `ScheduleFrequency` stays, documented as legacy-read-only.
    *   `ProtocolRecord` gains `startLocalDate`, `endLocalDate`, `period` and
        `remindersEnabled`.
    *   The schedule read model exposes the current version's `rule` and
        `effectiveFrom`.
    *   `DoseRecord` gains `utcOffsetMinutes` and a derived `localTime`.
    *   Doc comments that cite unpublished section numbers are rewritten to
        state the rule they rely on.

##### 14. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

*   **Type / Scope**: `ProtocolsRepository`. Edits are confined to the
    existing Protocols methods; new reads go in file 16.
*   **Proposed Changes**:
    *   `logDose` writes `utcOffsetMinutes` from `tookAt.timeZoneOffset`.
    *   The Schedule reconcile path writes versions per the version rules.
    *   Member removal inserts a `none` version instead of archiving the
        Schedule.
    *   Protocol create and edit write local-date bounds, `period` and
        `reminders_enabled`, validated by file 6.
    *   The sync image writers and readers for protocols, schedules and doses
        carry the new fields. Readers accept legacy images, upcasting through
        file 4, and never throw on a legacy `frequency`.

##### 15. `apps/mobile/lib/features/sync/repositories/sync_repository.dart` (Modify)

*   **Proposed Changes**: `syncProtocolVersion` 1 → 2.

##### 16. `apps/mobile/lib/features/protocols/repositories/protocol_plan_reads.dart` (Create)

*   **Type / Scope**: Repository reads.
*   **Proposed Changes**: Streams that build `PlanProtocol`s and `PlanDose`s
    from Drift and run the core:
    *   `watchPlannedDay(localDate)`;
    *   `watchConsistency(compoundId, from, to)`;
    *   `plannedTimes(from, to)`, for the reconciler.

    It owns the legacy bound conversion: a legacy instant becomes a local date
    in the device zone.

##### 17. `apps/mobile/lib/data/repositories/portable_archive_repository.dart` (Modify)

*   **Proposed Changes**: `archiveFormatVersion` 1 → 2. The reader accepts
    format 1 and 2. A format-1 archive's Schedules and Protocols import as
    legacy rows, read through the upcaster. Merge-only behavior is unchanged.

##### 18. `apps/server/src/sync.ts` (Modify)

*   **Proposed Changes**: `SYNC_PROTOCOL_VERSION` 1 → 2.

##### 19. `apps/server/src/agent-protocols.ts` (Modify)

*   **Proposed Changes**:
    *   Write schemas for Protocols gain `start_local_date`,
        `end_local_date`, `period` and `reminders_enabled`.
    *   Schedule writes take `rule` and `effective_from` and follow the version
        rules.
    *   Every write runs file 8's validators.
    *   Reads return the new shape, upcasting legacy payloads through file 8.
    *   The Dose `timezone` field description says it is a display
        abbreviation, and Doses gain `utc_offset_minutes`.

##### 20. `apps/server/src/observability.ts` (Modify)

*   **Proposed Changes**: Add the new payload keys to the privacy deny-list.

##### 21. Generated contract (Regenerate)

*   **Files**:
    *   `packages/contract/openapi.json`
    *   `packages/contract/src/agent-client.ts`
    *   `apps/mobile/lib/api/perennia_api_client.dart`
    *   `agent-skills/perennia/references/api-operations.md`
*   **Proposed Changes**: `pnpm --filter @perennia/contract generate` output,
    committed.

##### 22. `CONTEXT.md` (Modify)

*   **Proposed Changes**:
    *   Rewrite **Schedule**: when a member Compound is due on an active day,
        by days and times; versioned.
    *   Add **Schedule Version**, **Protocol Period**, **Pause**, **Planned
        Dose** ("derived, never stored"), **Untimed** and **Day Status**
        ("derived, never stored", with the seven values).

##### 23. Tests (Create/Modify)

*   `apps/mobile/test/data/protocol_plan_migration_test.dart` (Create):
    schema 57 → 58 on a seeded database. Every value survives, the foreign key
    check is clean, and a legacy `twiceDaily` row reads as untimed ×2.
*   `apps/mobile/test/features/protocols/protocols_repository_test.dart`
    (Modify):
    *   a version is inserted on a next-day edit, and updated in place on a
        same-day edit;
    *   member removal inserts a `none` version;
    *   `utcOffsetMinutes` is written;
    *   a legacy sync image is read through the upcaster.
*   `apps/mobile/test/data/portable_archive_repository_test.dart` (Modify): a
    format-1 archive imports.
*   `apps/server/test/agent-protocols.test.mjs` (Modify): validation rejects
    and warnings; legacy payload reads; version writes.
*   `apps/server/test/sync-convergence.test.mjs` (Modify): two devices write
    same-day versions offline and converge to the larger id; a version-1
    request is rejected.

#### Phase 3: the Planned list and the plan editor

##### 24. `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart` (Modify)

*   **Proposed Changes**:
    *   Bounds become date-only pickers.
    *   A "Period" section: an "Until" switch with an end date and an "N doses"
        helper that fills the end date from `endDateForDoseCount`; a "Cycle"
        switch with on days, off days and anchor date; and a pauses list with
        add, edit and remove.
    *   Each member's Schedule editor gains days (daily, weekdays chips, every
        N days) and times (a list of time pickers), or an untimed count, or "As
        needed".
    *   A "Reminders" switch. Turning it on requests notification permission
        the first time (CUJ 10).
    *   Rejects and warnings from file 6 show inline, as Dose validation does.

##### 25. `apps/mobile/lib/features/protocols/widgets/protocols_day_view.dart` (Modify)

*   **Proposed Changes**:
    *   A "Planned" section above the logged Doses, driven by
        `watchPlannedDay`. Its rows and "Log all planned" are as described in
        D6. It is hidden when the day has nothing planned.
    *   The log sheet's time picker gains a date field.
    *   The sheet prefills from the planned row when opened from one.
    *   The prefill from the last Dose's time of day is removed; time defaults
        to now.
    *   The amount still prefills from the last Dose of that Compound when it
        is opened outside the Planned list.

##### 26. `apps/mobile/lib/features/protocols/controllers/protocols_day_controller.dart` (Modify)

*   **Proposed Changes**: Expose the planned-day stream. "Log all planned"
    logs every pending planned dose for the day as one Batch through `logDose`.
    Doses are tagged with the planned Protocol and timed per D6.

##### 27. `apps/mobile/lib/l10n/app_en.arb` and generated `app_localizations*.dart` (Modify/Regenerate)

*   **Proposed Changes**: Strings for the editor, the Planned list, the seven
    status labels, the reminder copy, the permission-denied text and the
    status screen. No string uses a word D6 bans.

##### 28. Tests (Create/Modify)

*   `apps/mobile/test/features/protocols/protocol_screen_test.dart` (Modify):
    the period, pause and rule editors; validation messages; ≥ 48 dp targets.
*   `apps/mobile/test/features/protocols/protocols_day_view_test.dart`
    (Modify):
    *   the Planned list states;
    *   "Log all planned";
    *   two-tap logging from a row;
    *   the date field;
    *   labels present alongside color;
    *   contrast in both themes.
*   `apps/mobile/test/features/protocols/log_dose_sheet_test.dart` (Modify):
    prefill rules.
*   `apps/mobile/test/features/protocols/protocol_plan_reopen_test.dart`
    (Create): the app is killed during "Log all planned". After reopening, the
    Batch is either fully applied or absent, and the Planned list matches.

#### Phase 4: the consistency view

##### 29. `apps/mobile/lib/features/protocols/widgets/consistency_screen.dart` (Create)

*   **Proposed Changes**:
    *   Opens for one Compound, or for a Protocol, which shows a tab per
        member.
    *   A range picker: 30 days by default, 7, 90, 365, or custom up to 366.
    *   The chart (file 30) above a day list. Each day shows its status label,
        the logged times and amounts, and the planned times and amounts.
    *   It shows the existing "For personal tracking; not medical advice."
        notice.
    *   Entry points: the Compound's detail and the Protocol screen.

##### 30. `apps/mobile/lib/features/protocols/widgets/consistency_chart.dart` and `apps/mobile/lib/features/protocols/models/consistency_chart_data.dart` (Create)

*   **Proposed Changes**: An `fl_chart` scatter. X is the date and Y is the
    time of day. Each logged Dose is a point, and each planned time is a
    horizontal segment for the days it applies. Off-cycle and paused days are
    shaded and labelled. The model is pure and tested, following
    `effect_timeline_chart_data.dart`.

##### 31. `apps/mobile/lib/features/protocols/controllers/consistency_controller.dart` (Create)

*   **Proposed Changes**: Range state and the `watchConsistency` stream.

##### 32. Tests (Create)

*   `apps/mobile/test/features/protocols/consistency_screen_test.dart`: labels,
    the range picker, entry points, and none of the words D6 bans.
*   `apps/mobile/test/features/protocols/consistency_chart_data_test.dart`:
    planned segments across a version change (CUJ 6) and shading (CUJ 3 and
    5).

#### Phase 5: reminders

##### 33. `apps/mobile/pubspec.yaml` and `pubspec.lock` (Modify)

*   **Proposed Changes**: Add `flutter_local_notifications`, `timezone` and
    `flutter_timezone`, at their current stable versions at implementation
    time.

##### 34. `apps/mobile/lib/features/protocols/services/protocol_reminder_plan.dart` (Create)

*   **Type / Scope**: Pure Dart.
*   **Proposed Changes**:
    `desiredReminders(plannedTimes, dayStatusesToday, now, horizonDays: 14, cap: 48) -> [ReminderSpec{id, localDate, localTime}]`.
    *   It groups by (date, time).
    *   It drops past times and today's fully filled times.
    *   It takes the earliest 48.
    *   `id` is the 31-bit FNV-1a hash of `"protocolReminder:<date>T<time>"`.

##### 35. `apps/mobile/lib/features/protocols/services/protocol_reminder_scheduler.dart` (Create)

*   **Proposed Changes**: Wraps the plugin.
    *   On start, it initializes the timezone database and sets the local
        zone from `flutter_timezone`.
    *   `reconcile()` diffs `desiredReminders` against the pending
        notifications whose payload kind is `protocolReminder`, then cancels
        and schedules.
    *   It uses `zonedSchedule` with `inexactAllowWhileIdle`, title
        "Supplements", body "Planned for <localized time>", channel
        "Reminders", and `VISIBILITY_PRIVATE`.
    *   It runs on start, on resume, on any change to Protocols, Schedules or
        Doses (debounced 500 ms), after sync, and on the plugin's timezone
        change.
    *   It does nothing when the device setting is off, or when no Protocol
        has reminders enabled; in both cases it cancels all of its own
        notifications.

##### 36. `apps/mobile/lib/app.dart` (Modify)

*   **Proposed Changes**: Start the scheduler after the first frame, next to
    `TimerNotificationRouter.signalReady`. Route a `protocolReminder` tap,
    including one buffered from a cold start, to `ProtocolsLockGate`, then the
    Protocol Day for the payload's date.

##### 37. `apps/mobile/ios/Runner/AppDelegate.swift` (Modify)

*   **Proposed Changes**: In `didReceive` and `willPresent`, a notification
    whose identifier has the timer prefix keeps today's handling. Every other
    notification goes to `super`, so the plugin receives it. The plugin is
    registered as its docs require.

##### 38. `apps/mobile/android/app/src/main/AndroidManifest.xml` and `apps/mobile/android/app/build.gradle.kts` (Modify)

*   **Proposed Changes**: Register the plugin's `ScheduledNotificationReceiver`
    and `ScheduledNotificationBootReceiver`, the latter for `BOOT_COMPLETED`
    and `MY_PACKAGE_REPLACED`. Add `RECEIVE_BOOT_COMPLETED`. No exact-alarm
    permission. Enable core library desugaring, as the plugin requires.

##### 39. `apps/mobile/lib/features/settings/repositories/settings_repository.dart` (Modify)

*   **Proposed Changes**: Device-level `protocolRemindersOnThisDevice`, default
    true, in `settings.json`. Never synced.

##### 40. `apps/mobile/lib/features/protocols/widgets/protocol_reminders_settings.dart` (Create) and `apps/mobile/lib/features/settings/widgets/privacy_settings_screen.dart` (Modify)

*   **Proposed Changes**: A "Supplement reminders" tile under the existing
    Supplements lock tile. It holds the device switch and a status screen
    showing:
    *   the notification permission;
    *   the pending reminder count against the 48 cap;
    *   "Reminders scheduled through <date>";
    *   the last reconcile time and its trigger, held in memory only.

##### 41. Tests (Create)

*   `apps/mobile/test/features/protocols/protocol_reminder_plan_test.dart`:
    grouping (CUJ 1), dropping filled times (CUJ 2), off-cycle (CUJ 3), the
    cap and horizon (CUJ 11), id stability, and daylight-saving-change days.
*   `apps/mobile/test/features/protocols/protocol_reminder_scheduler_test.dart`:
    the diff against a fake plugin, the device switch off, lock-independent
    text, and the payload contents.
*   `apps/mobile/test/features/protocols/protocol_reminder_tap_test.dart`: a
    tap routes through the lock gate to the right date, from a cold start and
    from resume.

#### Phase 6: agent planned-day and status reads

##### 42. `apps/server/src/agent-protocols.ts` (Modify)

*   **Proposed Changes**: Two reads, `GET /agent/protocols/planned-days` and
    `GET /agent/protocols/day-statuses`.
    *   Query parameters, camelCase like the existing Dose list:
        `fromLocalDate` and `toLocalDate`, inclusive and at most 366 days
        apart; `today`, required; optional `compoundId` and `protocolId`;
        `detail=summary|doses`, default summary.
    *   Rows are filtered in SQL by user and entity type before the core runs.
        There is no full-table load.
    *   Responses carry statuses and counts only. They have no ratio or streak
        field.

##### 43. `apps/server/src/agent-mcp.ts` (Modify)

*   **Proposed Changes**: Matching MCP tools named like the existing ones,
    `agent_list_protocol_planned_days` and `agent_list_protocol_day_statuses`,
    with the same parameters.

##### 44. Generated contract (Regenerate)

*   **Proposed Changes**: As file 21, for the new routes.

##### 45. Tests (Modify)

*   `apps/server/test/agent-protocols.test.mjs`: range limits, the required
    `today`, filters, and summary vs detail.
*   `apps/server/test/agent-mcp-parity.test.mjs`: the new tools match REST.

##### 46. `docs/designs/SITEMAP.md` and this spec (Modify)

*   **Proposed Changes**: Status → Current once phase 6 merges.

### Verification Plan

*   **Build**: `flutter build apk --debug`, plus an iOS simulator build
    (`flutter build ios --simulator --debug`), run by hand at phase 5,
    because no CI job builds the platforms.
*   **Gate**: `pnpm ci:local --changed` green on every phase. The jobs that
    must pass:
    *   `golden` (phases 1, 2 and 6);
    *   `mobile` (every phase);
    *   `contract` (phases 2 and 6);
    *   `js` and `sync` (phases 2 and 6).
*   **Cross-language**: every m36 case passes in both languages. A case that
    passes in one and not the other fails the `golden` job.
*   **Standing scenarios**: kill-and-reopen during "Log all planned" (file
    28); sync convergence with same-day versions (file 23).
*   **Manual, on a device, at phase 5**:
    *   CUJ 1 at a near-future minute on an iPhone and an Android phone;
    *   lock on, with notification text checked on the lock screen;
    *   permission denied (CUJ 10);
    *   a reboot on Android, then a reminder still fires;
    *   a timezone change in system settings moves the next reminder (CUJ 8).
*   **Success**: the motivating user's stack from The Problem, entered as two
    Protocols ("Daily" and "Skin"), produces the reminders and statuses of
    CUJ 1 to CUJ 7 over two weeks of use on a device.

--------------------------------------------------------------------------------

<!-- Provenance: Indicates initial structural drafting via EGM. -->

*Drafted with EGM*
