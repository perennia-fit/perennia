# Protocol Schedules and Reminders

*   **Author:** Leonardo Pinheiro
*   **Status:** Approved
*   **Date:** 2026-10-25 (revised 2026-10-26 after Goldfish review; 2026-10-27 to record the decisions made building Phases 1 and 2; 2026-10-28 to record the decisions made building file 34a and Phase 3, to close the question on nearest-time matching, to record behaviour a drift report found, to record the decisions made building file 40a and Phase 4, to record the decisions made building file 46a and Phase 5, and to record the decisions made building Phase 6)

--------------------------------------------------------------------------------

## Overview

Perennia's Protocols domain lets a user record what they take: supplements,
vitamins, hormones, peptides, medications. In the app this section is labelled
**Supplements**, and it can be locked. A **Compound** is an item in the user's
own library. A **Dose** is one logged administration of it. A **Protocol** is a
named course of one or more Compounds, each with an optional **Schedule** saying
what the user intends to take. These terms are defined in
[CONTEXT.md](../../CONTEXT.md). This spec rewrites the definition of Schedule
and adds the terms in [New and changed terms](#new-and-changed-terms).

Today a Schedule is only an amount, a unit, a route, and one of six coarse
frequencies (once, twice or three times daily, every other day, weekly, as
needed). It has no time of day. The app never reminds the user of anything, and
it cannot show how closely the user follows the plan they wrote.

This spec makes the Schedule precise enough to plan against: when each dose is
due, on which days, and over what period. It then adds the three things that a
precise plan makes possible:

1.  **Reminders** at the planned times.
2.  **The Planned list**: a planned-versus-logged list at the top of the
    Protocol Day view, where the user logs what is due in one or two taps.
3.  **The Consistency view** for each Compound: what was taken, when, and how
    much, plotted against what was planned.

All three are computed from the plan and the logged Doses. None of them stores a
result. The same computation runs in the app (Dart) and on the server for
Agents (TypeScript), pinned together by shared test cases called golden vectors,
the way [validation](../../ARCHITECTURE.md#validation) already is.

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
*   Protocols data syncs like all other data, and the user's own Agent has the
    same access the app has.

This spec adds one more: **the plan belongs to the user, and the app only
mirrors it back.** Reminders fire because the user asked for them. Consistency
describes what happened against a plan the user wrote. Nothing is scored,
streaked, rewarded or marked as failed.

## The Problem

The users this is for train for both strength and endurance and care about
long-term health. They follow several protocols at once, each with its own
rhythm. A real example from one user:

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
    after a Protocol. But it can't distinguish a month of taking a Compound
    every day from a month of taking it four days a week. Without that, the
    Effect view can mislead.

The existing Schedule can't fix either problem. With no time of day there is
nothing to remind at. With frequencies like "twice daily" or "weekly", which
have no times, no weekday and no starting day, the app can't work out which
days a dose was due, so it can't show which days have nothing logged. On/off
cycles can't be described at all. A course's end can only be one end date on
the whole Protocol.

## Goals

1.  **A Schedule describes when doses are due.** The user can say:
    *   **at what times:** one or more clock times a day, or a count per day with
        no fixed time;
    *   **on which days:** every day, chosen weekdays, or every N days;
    *   **over what period:** ongoing; until an end date (with a helper that
        turns "20 doses" into an end date); or a repeating on/off cycle such as
        60 days on and 30 off.

    The user can also pause a Protocol and end it early. These are part of the
    plan, not a record against a dose. A pause lets a deliberate break read
    "Paused" instead of "Not logged", and silences reminders, without ending
    the Protocol and starting a new one.
2.  **One reminder per planned time.** All planned doses due at the same minute
    share one notification. Its text never names a Compound, and tapping it
    opens the app through the lock to that day's Planned list. Reminders are
    off until the user turns them on for a Protocol.
3.  **The Planned list,** inside the locked Protocol Day view. Logging one
    planned dose takes at most two taps, and logging everything due takes one
    action. This follows the rule that
    [logging a repeat set must take ≤ 2 taps](../../AGENTS.md#ux-rules-of-thumb).
4.  **The Consistency view for each Compound** over a chosen date range. Each
    day gets one Day Status from a closed set, and the view shows the actual
    times and amounts next to the planned ones. It returns statuses and counts
    only: never a percentage, a score or a streak.
5.  **Agents get the same answers.** The new Schedule shape can be read and
    written through the Agent API in the same release as the app. The planned
    days and the Day Statuses come to the Agent API in a later stage of the same
    feature. One shared definition, in Dart and TypeScript, produces every
    answer, pinned by golden vectors that both test suites run.
6.  **Logged history survives.** Every existing Compound and Dose keeps
    reading correctly. Protocol plans entered before this change (Protocols,
    their members, Schedules and target outcomes) are cleared once and
    re-entered, because nothing has shipped (D3). Doses keep their Protocol tag
    and name snapshot, so they still render and still count.
7.  **The vocabulary is defined.** [CONTEXT.md](../../CONTEXT.md) gains the
    domain terms below, and the Schedule entry is rewritten, in the
    implementation pull request.

## New and changed terms

The first group are domain terms and go into CONTEXT.md. The second group are
names used in this spec and in code only.

| Term | Definition | CONTEXT.md |
| :--- | :--------- | :--------- |
| **Schedule** (rewritten) | When a Protocol Member's Compound is due on a day its Protocol is in effect: by days and times, with a planned amount, unit and route. Versioned: it is the Schedule Version that applies on a date. | yes |
| **Schedule Rule** | The days-and-times part of a Schedule: every day, chosen weekdays or every N days; a list of clock times or a count of untimed doses; or "as needed". | yes |
| **Schedule Version** | One stored state of a Protocol Member's Schedule, with the local date it applies from (`effectiveFrom`). Authored plan history, never a result. | yes |
| **Protocol Period** | When a whole Protocol is in effect: its start and end dates, an optional on/off cycle, and its Pauses. | yes |
| **Pause** | A date range, inclusive at both ends, when a Protocol plans nothing. | yes |
| **In effect** | A Protocol is in effect on a date when the date is within its bounds, it isn't paused, and it isn't in a cycle's off-period. Distinct from **Active**, which keeps its CONTEXT.md meaning of "not archived". | yes |
| **Protocol Member** | One Compound inside a Protocol, with its Schedule Versions. | yes |
| **Planned dose** | One dose a Schedule plans on a date, with a clock time or untimed. Derived, never stored. A logged record is always a **Dose**; a computed one is always a "planned dose". | yes |
| **Untimed** | A planned dose with no clock time. It counts like any other, but never gets a reminder. | yes |
| **Day Status** | The single label for one Compound on one date, from the closed set in D6. Derived, never stored. | yes |
| **Planned list** | The planned-versus-logged list at the top of the Protocol Day view. | no |
| **Consistency view** | The per-Compound view of logged Doses against planned doses over a date range. | no |
| **Reminder reconciler** | The device-local component that keeps the phone's scheduled reminders equal to what the plan says. | no |
| **Scheduling horizon** | How far ahead the reminder reconciler schedules reminders (D5). | no |

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
*   **A per-Dose "skip today" record.** A planned dose that wasn't logged reads
    "Not logged".
*   **CSV export of Protocols data.** The exclusion stays as it is.
*   **Cancelling reminders on other devices through Sync Nudge** (Alternative
    O).
*   **A cycle-aware Effect view.** In v1, the Effect view counts off-cycle and
    paused days as "during" a Protocol, and says so on screen (D6).
*   **Exact Android alarms.** v1 uses inexact delivery (D5).
*   **Any stored result:** no stored Day Statuses or reminder history. Nothing
    records that a reminder fired, was tapped or was dismissed.

The deferred items, with what each one needs before it can be built, are listed
under [Future Improvements](#future-improvements).

## Open Questions

None open. The questions settled while drafting map to decisions: Schedule
history → D1; the time model → D2; the sync cutover → D3; where the period
lives → D4; the notification stack → D5.

Building Phase 1 raised questions this spec had not answered. They are now
settled in the sections they belong to:

*   output order, coverage and counts → [Shared core API](#shared-core-api-pure-dart-and-typescript-mirror-each-other);
*   dates before an anchor → D4;
*   Doses with no PlanDay → D6;
*   codec strictness, issue order, `amount_required`, sorting, and the new
    `pause_count` and `amount_absent` checks → D7;
*   the UTC offset range → D2.

The new rules land in Phase 2 (file 17a).

Building Phase 2 raised more. They are settled the same way:

*   start-date moves, default anchors and the base an unchanged save is
    compared with → D1;
*   the shared-core reading of a default anchor → D4 and
    [Shared core API](#shared-core-api-pure-dart-and-typescript-mirror-each-other);
*   the Agent surface: which writes carry `today`, field naming, whole-row
    writes, archived rows, unchanged Schedule writes, rule ids and warnings
    → D6;
*   the storage form of `rule` and `period` → [Data shapes](#data-shapes-fixed-by-this-spec);
*   the offset range on Dose writes → D2.

The decisions that change what Phase 2 built land as file 34a.

Building file 34a and Phase 3 raised more. They are settled the same way:

*   which members an earlier start move copies, ties on the earliest date,
    and what a copy stores → D1;
*   the Protocol-row comparison and where a default anchor is moved → D1
    and D4;
*   a Protocol tombstoned by undo, and the issues reported beside
    `protocol_archived` → D6;
*   where the Agent path sorts times and weekdays → file 29;
*   the Planned list: when "Log all planned" shows, what tapping a Logged
    row does, a future day in the log sheet, its date field, the day
    boundary, and how an edited Dose's time reads → D6;
*   the clock, the one-shot read and `today` → files 35 and 37;
*   which day the Compound list logs on → file 38.

The decisions that change what file 34a and Phase 3 built land as file
40a.

A drift report against the built code found behaviour the spec hadn't
stated. It is recorded as built, where it applies:

*   a first Schedule for a member that had none → D1;
*   an Agent Dose's local date, and archiving a target outcome → D6 and
    file 29;
*   the codecs' ceilings and their errors for a period under one day →
    [Shared core API](#shared-core-api-pure-dart-and-typescript-mirror-each-other),
    D7 and files 3, 8, 13 and 17a;
*   the planned-day types, and "Log all planned" with an incomplete row →
    files 35 to 37.

Building Phase 3 raised one more question, settled before Phase 4 was
built: nearest-time matching stays as built, with no change to its code or
vectors. A Dose logged from the Planned list on today is timed now, and it
fills the timed slot nearest that time (D6). So it can fill a later slot
than the row that was tapped: a Dose logged at 12:00 against a 09:00 row
fills a 13:00 slot instead, and the 09:00 row stays "Pending". "Log all
planned" does the same: at 12:00 it logs the due 09:00 dose, which then
fills 13:00. This is accepted. Recorded times stay true, and the Effect
estimate reads them. Moving a late Dose onto an earlier slot would reverse
the case D6 argues for, where a Dose at 20:50 fills a 21:00 slot rather
than an unfilled 09:00 one. The 13:00 reminder doesn't fire, because its
slot is filled, and that is accepted as part of the same rule (see Risks).
Phase 4's Consistency view shows which slot each Dose filled, which makes
the outcome visible.

Building file 40a and Phase 4 raised more. They are settled the same way:

*   a member archived on its earliest version's date → D1;
*   how a "Logged" row finds its Dose, the frame an edited Dose's date
    and time are held in, the frame of the edit sheet's "today", and the
    order of the day's Dose rows → D6 and file 40a;
*   the Consistency view: its range and day boundary, its tabs, the lock,
    the chart and how its shading is labelled, the day list, and planned
    against logged masses → D6 and files 41 to 45;
*   `watchConsistency`'s `today` and range limits, and how `sequence` is
    numbered over a range → file 44;
*   the new strings and the performance README row → files 41 and 46.

Two findings change what was built and land as file 46a: one helper for
a Dose's clock time at its frozen offset, where three copies exist, and
the day's Dose rows in matching's order rather than instant order.

Building file 46a and Phase 5 raised more. They are settled the same way:

*   what "clock order" means for the day's Dose rows and the Consistency
    read, the helper's name, and the edit sheet's "today" → D6 and file
    46a;
*   how iOS routes a notification, and the options a reminder shows with
    in the foreground → D5 and file 53;
*   when the reconciler runs, when a run schedules every reminder again,
    what makes it schedule none, a run that fails, and an unknown zone id
    → D5 and file 49;
*   the horizon's days, a planned time a daylight-saving change skips or
    repeats, and the archive day → D5 and file 48;
*   what "a Protocol has reminders on" and "the first time" mean, where
    "Reminders scheduled through" shows, a tap for the Protocol Day
    already open, and the time format → D5 and files 52 and 56 to 58;
*   the files and repository reads no entry listed, and the tests file 60
    leaves out → files 50 to 52 and 60.

Two findings change what was built and land as file 60a. On iOS, the
plugin's list of pending notifications likely fails while a rest-timer
notification is pending, which leaves reminders stale until a later run.
And `willPresent` uses presentation options that need iOS 14 in an app
whose deployment target is iOS 13.0.

Building Phase 6 raised more. They are settled the same way:

*   the two reads' response envelopes, field names and enums, their 400
    body, how the range is counted, and the `today` bound on the Day
    Status read → D6;
*   what the Day Status read returns with a `protocolId`, and how that can
    differ from the app → D6;
*   rows the reads can't use, and a member whose Compound row is missing
    → D6 and file 61;
*   the filter keys, which file 61 named wrongly → file 61;
*   the server's read-latency budget, which file 65 assumed but didn't
    exist → file 65 and [Non-Functional Requirements](#non-functional-requirements);
*   the observability deny-list keys, and the files no entry listed →
    files 64 and 65 and [Non-Functional Requirements](#non-functional-requirements);
*   when Status becomes Current → file 66.

None of them changes what Phase 6 built, so there is no lettered entry
after file 65.

## Critical User Journeys (CUJs)

### CUJ 1: Morning stack, one reminder

*   **Given**: A Protocol "Daily" with reminders on, holding TRT (09:00),
    AgeMate (09:00) and creatine (17:00). Nothing is logged today.
*   **When**: It is 09:00, and later the user taps the notification.
*   **Then**: One notification arrives, reading "Planned for 9:00 AM". On
    Android it can arrive later (D5). It names no Compound. Tapping it opens the
    Supplements section (after the PIN or biometric prompt, if the lock is on)
    on today's Protocol Day. The Planned list shows TRT, AgeMate and creatine as
    "Pending". One tap on "Log all planned" records TRT and AgeMate at their
    planned amounts, timed now. Their rows then read "Logged". Creatine stays
    "Pending", because its 17:00 time hasn't come.

### CUJ 2: A Dose logged before its reminder

*   **Given**: The CUJ 1 setup. The user logs TRT at 08:40 from the Planned
    list, but not AgeMate.
*   **When**: It is 09:00.
*   **Then**: The 09:00 notification still fires, because AgeMate is still due.
    If both had been logged before 09:00, it would not fire on this device.

### CUJ 3: Off-cycle days

*   **Given**: A Protocol "Skin" holding GHK-Cu at 21:00 daily, with a cycle of
    60 days on and 30 days off, anchored on 2026-09-01. Cycle days count from 0
    at the anchor.
*   **When**: The date is 2026-11-05, cycle day 65, inside the off-period (days
    60-89).
*   **Then**: No reminder fires and the Planned list doesn't show GHK-Cu. In the
    Consistency view the day reads "Off cycle", not "Not logged". On 2026-11-30,
    cycle day 90 and so day 0 of the next cycle, the 21:00 reminder starts
    again.

### CUJ 4: A course that ends

*   **Given**: The user creates a Protocol "Shoulder" for BPC-157 at 21:00
    daily, starting 2026-10-26, and uses the helper to turn "20 doses" into an
    end date. The helper sets 2026-11-14.
*   **When**: The date passes 2026-11-14.
*   **Then**: No more reminders, and the Protocol shows as ended. Doses logged
    on that course keep their Protocol tag and still show in its Effect view.

### CUJ 5: Pausing after a reaction

*   **Given**: "Skin" is in an on-period. The user pauses it from 2026-10-10 to
    2026-10-16.
*   **When**: Those dates arrive, and later the user opens the Consistency
    view.
*   **Then**: No reminders fire during the pause. Those seven days read
    "Paused", not "Not logged". The cycle doesn't shift: day 0 is still
    2026-09-01.

### CUJ 6: Editing a plan mid-course

*   **Given**: TRT has been planned daily at 09:00 since 2026-09-01. On Monday
    2026-10-19 at 06:30, the user changes it to Monday, Wednesday and Friday at
    07:00.
*   **When**: The user opens TRT's Consistency view.
*   **Then**:
    *   Days before 2026-10-19 are still compared against daily at 09:00.
    *   From 2026-10-19, only Mondays, Wednesdays and Fridays have a planned
        dose, so Tuesday 2026-10-20 reads "Not planned" (not scheduled that
        day), not "Not logged".
    *   The chart's planned line moves from 09:00 to 07:00 on 2026-10-19.
    *   The 07:00 reminder fires on 2026-10-19. Had the edit been made at
        08:00, that day would get no reminder, because 07:00 had passed.

### CUJ 7: A Dose logged late, for last night

*   **Given**: GHK-Cu is planned at 21:00. The user took it at 21:05 but logs it
    at 00:30.
*   **When**: The user opens yesterday's Protocol Day and taps the GHK-Cu row.
*   **Then**: The log sheet opens with yesterday's date and 21:00, both
    editable. Saving records the Dose on yesterday's Protocol Day, and the row
    reads "Logged". Had the user opened the log sheet outside the Planned list,
    its date field would let them set yesterday the same way.

### CUJ 8: Travel

*   **Given**: TRT is planned at 09:00. The user flies from São Paulo to Lisbon.
*   **When**: The phone's timezone changes, and later the user opens the app.
*   **Then**: From that next open or resume, reminders follow 09:00 Lisbon time.
    Until then, reminders already scheduled fire at their São Paulo instants.
    Doses already logged keep their own local date and time as recorded, and
    past days never regroup.

### CUJ 9: A second device, or an Agent, logs first

*   **Given**: The user has two signed-in phones, both with reminders on. At
    08:55 their Agent logs TRT through the API.
*   **When**: It is 09:00 and the second phone hasn't synced since 08:00.
*   **Then**: The second phone's reminder may still fire for TRT. When the user
    opens the app on it, the app syncs, and the Planned list shows TRT as
    "Logged". Each phone has a local "Reminders on this device" switch for
    anyone who doesn't want them twice. This limitation is accepted; see
    Alternative O.

### CUJ 10: Notification permission denied

*   **Given**: The user turns on reminders for a Protocol and declines the
    system's notification permission.
*   **When**: The user returns to the Protocol screen.
*   **Then**: The Reminders switch shows "Notifications are off for Perennia",
    with a button to the system settings. The Planned list and the Consistency
    view work as usual.

### CUJ 11: Not opening the app for weeks

*   **Given**: Reminders are on, and the user doesn't open the app for 20 days.
*   **When**: The scheduling horizon runs out (D5).
*   **Then**: Reminders stop at the horizon. The Protocol screen and the
    reminder status screen both show "Reminders scheduled through <date>", so
    the stop is visible rather than silent. Opening the app schedules the next
    horizon.

### CUJ 12: A second phone without notification permission

*   **Given**: The user turned reminders on for "Daily" on phone A. Phone B
    syncs the Protocol, has its device switch on, and has never been asked for
    notification permission.
*   **When**: The user opens the Protocol Day view on phone B.
*   **Then**: A banner reads "Reminders are off on this device", with an
    "Allow" button that requests permission. Until then phone B schedules no
    reminders.

## Technical Plan (Architecture)

### Shape of the change

```text
                 authored, synced                      derived, never stored
   ┌──────────────────────────────────────┐   ┌──────────────────────────────────┐
   │ Protocol                             │   │ Protocol Plan core (pure)        │
   │   start/end local dates, period      │   │   Dart: apps/mobile/lib/domain/  │
   │   (cycle, pauses), remindersEnabled  │──┐│         protocols/               │
   │ Schedule Versions (per member)       │──┼▶   TS:   apps/server/src/         │
   │   effectiveFrom, rule, amount        │  ││                                  │
   │ Dose                                 │──┘│ planDays(protocols, from, to)    │
   │   localDate, timezoneOffsetMinutes   │   │ dayStatuses(planDays, doses,     │
   └──────────────────────────────────────┘   │             today)               │
                                              │ dueUnfilled(dayStatuses, today,  │
                                              │             now)                 │
                                              └───────────┬──────────────────────┘
                                ┌─────────────────────────┼─────────────────────┐
                                ▼                         ▼                     ▼
                         Planned list            Consistency view     Reminder reconciler
                         (Protocol Day view)     (per Compound)       (device only,
                                                                       never synced)
                                     Agent REST/MCP reads (later stage)
                                golden vectors pin Dart == TypeScript
```

Every surface asks the same core two questions: "what was planned on these
dates?" and "how did the logged Doses line up with it?". No surface reads a
Schedule directly. This copies the routine "Up next" pattern already in the
repository: a pure Dart function
(`apps/mobile/lib/domain/training/routine_up_next.dart`), its TypeScript twin
(`deriveAgentRoutineUpNext` in `apps/server/src/agent-plan-reads.ts`), and one
vector file with a JSON Schema that both test suites run
(`packages/golden-vectors/vectors/m34-routine-up-next.json`).

### D1. Schedules keep their history

Every edit to a Schedule inserts a new **Schedule Version**: a new row with its
own id. No version is ever edited in place.

*   **Which version applies.** For any date, the version that applies is the
    one with the latest `effectiveFrom` on or before that date. Several
    versions can share a date: several edits on one day, or two devices editing
    offline on the same day. Then the one with the largest id wins. Ids are
    UUIDv7, which sort by creation time, so that is the latest edit, and every
    device and the server agree.
*   **When a version starts.**
    *   A member created together with its Protocol, or while the Protocol's
        start is still in the future, gets a first version dated from the
        Protocol's start. So a Protocol created today with a start date in the
        past plans those past days.
    *   A member added to a Protocol that has already started gets a first
        version dated today. So adding creatine to a months-old "Daily"
        Protocol doesn't turn its past days into "Not logged".
    *   A member that already exists with no versions, and is then given a
        Schedule, is dated the same way as an added member: today, or the
        Protocol's start while that is still ahead. Both writers do this.
        Before, the row covered every date and read `no_schedule` (below).
        Now it covers the dates from that first version, so by the coverage
        rule its earlier days read `removed`, not `no_schedule`. Either way
        they read "Not planned", and no past day turns into "Not logged".
    *   Every later edit is dated `max(today, the latest existing
        effectiveFrom for that member)`, so an edit can never land behind an
        existing version and be hidden by it.
    *   An edit takes effect that same day (CUJ 6).
*   **Moving the start date later** inserts nothing. The version that
    applies on the new start is already the latest one dated on or before
    it, and dates before the new start read `outside`.
*   **Moving it earlier** inserts, for each member that was planned from the
    old start, a copy of its earliest version dated from the new start, so
    those members plan the new days. Versions are still never edited.
    *   **Which members.** Every member row of the Protocol whose earliest
        version is dated on or before the old start and after the new
        start. That includes archived (removed) members, which were part of
        the course from its start and still cover those days up to their
        `archived_on`. It excludes rows tombstoned by undo (they never
        existed), members with no versions (they already cover every date),
        and members whose earliest version is after the old start: a
        Compound added mid-course keeps its own first date, so moving the
        course's start doesn't turn days before it was added into "Not
        logged".
    *   **A member removed before it planned anything** gets no copy. That
        is a member whose `archived_on` is before its earliest version, such
        as one added while the start was still ahead and removed before the
        start came. It planned no day, so it was not planned from the old
        start, and a copy would turn days that were never in its plan into
        "Not logged". Its `archived_on` is read as stored before the save,
        so a member the same save removes still gets its copy. (Settled
        after file 34a's build, which copies such a member; file 40a.)
        *   **"Before" is strict.** A member covers dates through its
            `archived_on`, inclusive, so one archived on its earliest
            version's date planned that day, and it still gets its copy.
            Only an `archived_on` strictly before that date skips the
            member. The server skips a member only when its stored
            `archived_on` is a valid date; the app never stores another
            kind, because sync and import refuse a malformed one.
            (Settled after file 40a's build.)
    *   **Known limit: a later move, then an earlier one.** If the start
        moves later past a member added mid-course, and then moves earlier
        again, that member's earliest version is now on or before the old
        start, so it gets a copy, and its days before it was added read
        "Not logged". Nothing stored tells it apart from a member that was
        planned from the start: a member planned from an earlier start has
        the same shape. Telling them apart would need a new column on the
        member row, which this spec doesn't add. The case needs two start
        moves in opposite directions around a mid-course addition, so it
        is accepted.
    *   **Within one save.** Copies are taken from the rows and versions
        stored before the save. A member the same save removes gets its
        copy like any stored member, and is then archived. A member the same
        save adds gets its first version by the first-version rule above.
        The save's own Schedule edits are dated after the copies.
    *   **No ties.** A copy is dated before every version its member has,
        and an edit on or after the latest, so a copy never shares a date
        with an edit, and the new start never already holds a version of a
        member that gets a copy.
    *   The copy's rule and amount are the earliest version's. When
        several versions share the earliest date, the copy is of the one in
        effect on it, the larger id, as "Which version applies" reads it. A
        default anchor in the copy needs no rewriting, because it is read as
        the start (below). Both writers still store the new start there, as
        every write of theirs stores the start of the save, and that plans
        the same as keeping the source's date.
*   **Default anchors follow the start.** An every-N or cycle anchor left at
    its default (`anchor_is_default: true`) means "the Protocol's start",
    and is read that way when planning (D4), on every version. Moving the
    start moves it everywhere without writing anything. An anchor the user
    set stays where it is. Reading it at plan time, rather than copying
    every later version with a moved anchor on each start move, keeps one
    row per edit. It also covers a version another device or an Agent
    wrote before it saw the start move. And it matches how the rest of the
    period behaves: the start is a Protocol field, which is not versioned
    (below), so moving it reclassifies past days as any period edit does.
*   **Saves that change nothing** insert nothing. The editor sends every
    member's Schedule on every save, and only one that differs from the
    member's current version (the latest `effectiveFrom`, then the larger
    id) becomes a new version. The current version is the comparison base,
    not the version in effect today: a new version is dated `max(today,
    latest effectiveFrom)`, and the current version is the one in effect on
    that date. When a version is dated in the future (a Protocol whose
    start is still ahead), the version in effect today is an older one or
    none, and comparing with it would insert a copy of the current version.
    Two versions are the same when their decoded rules and amounts are
    equal, ignoring the stored date of a default anchor, which is never
    read. The app compares the Protocol row the same way: a stored `period`
    whose default cycle anchor holds another date (an Agent's write, say)
    equals the save's period, so an unchanged save leaves the row alone.
    Agent writes don't follow this rule (D6).
*   **No Schedule.** A member can have no Schedule, as today. A member with no
    versions, or whose version that applies has the rule kind `unscheduled`,
    plans nothing, and reads "Not planned" with the reason `no_schedule`.
    Clearing a Schedule in the editor inserts an `unscheduled` version.
    A member row with no versions has no first date, so it covers every date
    up to and including its `archived_on` (every date, when it is not
    archived), and reads `no_schedule` on each of them, not `removed`.
*   **Undo.** Undoing an edit tombstones the version row it inserted, as the
    Activity Log does for any insert. Tombstoned versions are ignored. A
    member row tombstoned by undo (which has `deleted_at` but no
    `archived_on`) is ignored entirely: undo means it never existed.
*   **Removing a Protocol Member** archives the member row, as today. That
    archive is the one record of the removal. The archive stores its local
    date, `archived_on`, frozen when it is written, as a Dose freezes its
    `localDate`. So no reader converts a timestamp, and travel never moves it.
    *   The archive day itself is still planned, the same as ending a Protocol
        early: a Dose logged that morning still counts.
    *   From the next day on, the member reads "Not planned" with the reason
        `removed`.
*   **Re-adding a Compound** creates a new member row, as today, with a first
    version dated today. Each member row covers the dates from its first
    version through its `archived_on`. Within a Protocol, the core takes, for
    each date, the member row of that Compound that covers it. When two rows
    cover the same date (removed and re-added the same day), the newer row
    (larger id) wins. So a removal and a later re-add read as one continuous
    history with a gap of "removed" days.
*   **Archived Protocols** keep their versions and freeze an `archived_on`
    the same way. Past days still count an archived Protocol up to and
    including that date. An archived Protocol is read-only: the app's editor
    refuses to edit one, and so does the Agent write path (D6). No path
    restores an archived Protocol or Protocol Member. Clearing an archive
    would erase its `archived_on`, so the days it read "removed" would turn
    back into planned days. Coming back is a new member row (above), or a
    new Protocol.

Versioning matters because a Schedule edit changes what was planned, and so
changes past Day Statuses. Changing daily to Monday, Wednesday and Friday would
otherwise turn two months of daily Doses into extras. Changing two doses a day
to one would turn "Partly logged" days into "Logged". Without versions, every
edit would rewrite how the past reads, which defeats the Consistency view (see
The Problem). The chart's planned line shows the history too (CUJ 6).

This is the authored plan's own history, the same kind of data as the
Protocol's dates. It is not a stored result.

**Only Schedules are versioned.** A Protocol's dates, cycle and Pauses are not.
Editing them reclassifies past days, which is how the user corrects the record.
Cycle-length changes mid-course are rare. If two devices edit a Protocol's
Pauses at once, last-writer-wins keeps one, and the other stays recoverable from
the Activity Log, as for any row. See Risks.

### D2. Dates and times are local, and the core is timezone-free

*   **Protocol bounds become local dates.** The start and end are stored as
    `YYYY-MM-DD` strings, with an inclusive end, replacing the instant columns
    (D3). A UTC instant has no stable
    calendar day: midnight on 2026-09-01 in Tokyo is 15:00 UTC on 2026-08-31.
    A cycle anchored by that instant would start a day early on any device that
    reads the date in UTC.
*   **Planned times are wall-clock times,** `HH:MM`. They follow the phone
    wherever it goes (CUJ 8).
*   **Each Dose freezes its UTC offset.** A new `timezoneOffsetMinutes` column
    is set at log time, next to the existing `localDate`. The name and meaning
    match the field Metric Readings already use
    (`apps/server/src/metric-reading-normalization.ts`,
    `apps/mobile/lib/domain/metrics/reading_normalization.dart`). Together with `tookAt`, it
    gives the Dose's local clock time permanently. The existing `timezone` column
    holds an abbreviation such as "BRT", which can't be converted back. It stays
    as a display label, and the Agent contract's description of it is corrected
    to say so. The same abbreviation problem in Workouts and Nutrition is out of
    scope.
*   **Doses without an offset.** A Dose logged before this change has a null
    `timezoneOffsetMinutes`. The app works out its local time in the device's
    current zone, and the server in UTC. The two can disagree on these older
    Doses; this is accepted and listed in Risks. On Agent Dose writes,
    `timezoneOffsetMinutes` is optional. When it is absent and `timezone` is a
    valid IANA zone name such as `America/Sao_Paulo`, the server derives it from
    `tookAt`. The server already has two copies of a `localDateInTimezone`
    helper (in `agent-plan-materialize.ts` and `agent-workout-batch-write.ts`).
    Phase 2 moves them into one shared helper used by all three callers,
    rather than copying it a third time.
    Otherwise it stays null.
*   **Bounds into Effect.** The Effect view's math is unchanged: it works on
    instants, with half-open windows. A new pure function in both languages,
    `effectBoundsFromLocalDates(startLocalDate, endLocalDate?, timezoneOffsetMinutes)`,
    converts a Protocol's local-date bounds into Effect's input. Start becomes
    local midnight of the start date. End becomes local midnight of the day
    after the inclusive end date. The app passes the device's current offset.
    The Agent Effect read gains an optional `timezoneOffsetMinutes` query parameter,
    default 0 (UTC), documented as such.
    *   **Offset range.** The offset is a whole number of minutes from −720
        to +840 (UTC−12:00 to UTC+14:00, the span of real zones). The
        function throws a `RangeError` for a fractional offset, and, from
        Phase 2, for one outside that range. The Agent Effect read returns
        400 for an offset outside it, before calling the function. An Agent
        Dose write's `timezoneOffsetMinutes` has the same range, and is a
        400 outside it.
    *   **Where the range lives.** Each language keeps it as a private
        pair of constants, not part of `ProtocolPlanValidationLimits`,
        because it is not a D7 check. Dart keeps it in `effect.dart`. The
        server keeps one pair in `agent-protocols.ts`, used by both Agent
        schemas and its `effectBoundsFromLocalDates`. The `effect_bounds`
        vectors pin both ends, so the two can't drift unnoticed.
*   **The shared core never sees a timezone.** It takes and returns local dates
    and `HH:MM` strings, and receives "today" as an input. The server never
    works out "today" for a user; Agent requests carry it (D6). Daylight-saving
    and travel handling lives only in the device's reminder reconciler:
    *   a time that doesn't exist on a daylight-saving change day fires at the
        first valid minute after the gap, so 02:30 fires at 03:00;
    *   a time that occurs twice fires once.

### D3. Hard sync cutover, and pre-change plans are re-entered

The app is unreleased, so there are no clients in the field to keep working.
`SYNC_PROTOCOL_VERSION` goes from 1 to 2 in `apps/server/src/sync.ts`. The sync
request schemas already require the version as a literal, so a version-1 client
is rejected with an error. Without the bump, it would push its incomplete copy
of a Schedule row and erase the fields it doesn't know.

The new plan data lives inside the existing `protocols` and `schedules` rows:
new typed columns, plus one JSON column each for the period and the rule. No
new synced entity type is added.

**Protocol plans entered before this change are cleared once, and re-entered.**
Nothing has shipped. The only data in that shape is developer data, and converting it would need permanent compatibility code for users
who don't exist (Alternative P).

*   **What is cleared.** The device's Drift migration and a server migration
    each delete every row of four tables: `protocols`, `protocol_compounds`,
    `schedules` and `protocol_target_outcomes`. The device migration doesn't
    mark anything as pending sync, so it pushes nothing.
*   **What is kept.** Compounds and Doses are untouched. A Dose keeps its
    Protocol tag and the Protocol name it captured, so it still renders, still
    counts, and still appears in its Compound's Consistency view.
*   **Older archives.** A portable archive written before the change imports
    its Compounds and Doses, and skips its Protocol plan rows.
*   **Activity Log.** An entry recorded before the change for one of the four
    tables can't be reverted. Undo already refuses an entry whose row no
    longer exists (the `missing` conflict in the app, `skipped_missing` on the
    server), so no new guard is needed.
*   **Re-entering.** The developer test-data generator today creates no
    Compounds, Protocols or Doses. It gains the motivating stack, with its
    Compounds and Doses over the generator's date range, in the same phase
    as the clear (Phase 2), so plans for development are one command away.

There is no read-time conversion and there are no legacy columns. Every
Protocol has local-date bounds, and every Schedule Version has a rule and an
`effectiveFrom`.

### D4. The period lives on the Protocol; days and times live on each Schedule

A **Protocol Period** says when a whole Protocol is in effect:

*   **ongoing**: from the start date, no end;
*   **until**: from the start date to an end date, inclusive. The "N doses"
    helper only computes this end date (D6); it stores nothing else;
*   **cycle**: N days on, M days off, repeating from an anchor date, which
    defaults to the start date. Cycle days count from 0 at the anchor, so a
    date is on-cycle when (date − anchor) mod (N + M) < N. A user already three
    weeks into a cycle sets the anchor in the past. A cycle may also have an end
    date.

**Pauses** are date ranges on the Protocol, inclusive at both ends, and always
with an end date; "end early" covers an open-ended stop. A paused day plans
nothing and reads "Paused". A pause doesn't shift a cycle: the anchor stays
where it is (CUJ 5). Ending early sets the end date to today, and today's
remaining planned doses are still planned.

A **Schedule Rule** says when a member's Compound is due on a day its Protocol
is in effect:

*   **days**: every day, chosen weekdays, or every N days from an anchor date,
    which defaults to the Protocol's start. A date is due when
    (date − anchor) mod N = 0;
*   **times**: a list of `HH:MM` times, or a count of untimed doses;
*   the planned amount, unit and route, as today;
*   or **as needed**, which plans nothing.

**An anchor fixes a phase, not a first day.** Both the cycle and the every-N
formulas use a floor modulo, whose result is never negative. So dates before
an anchor follow the same rhythm, counted backwards from it. An anchor can be
after the start: D1 keeps a user-set anchor when the start moves earlier, and
the user can pick a later one. The days between the start and that anchor are
then planned in step with the anchor. For example, every 3 days anchored on
2026-10-05 is due on 2026-10-02. A cycle of 3 on and 2 off anchored on
2026-10-05 reads 2026-10-01 to 2026-10-02 as on (cycle days −4 and −3, which
are days 1 and 2), and 2026-10-03 to 2026-10-04 as off. No validator rejects
an anchor after the start.

**A default anchor is the start.** An anchor stored with
`anchor_is_default: true` is read as the Protocol's `startLocalDate`, both
for a cycle and for every N days, whatever date is stored with it. Every
reader does this: `planDays` and `endDateForDoseCount` in the core, and the
editor, which shows the start. The stored date is kept so a row is still a
complete rule on its own, and is whatever its writer stored. The app stores
the start at the time of the save, in every version and period it writes.
On a start move, both writers store the new start in a copy's default
every-N anchor (D1) and in the period's default cycle anchor. The Agent path
moves a default anchor only on a start move; on any other write it stores
the anchor as sent. Nothing plans from the stored date. An anchor stored with
`anchor_is_default: false` is read as stored. This is what lets a start move
leave every version untouched (D1).

Putting the period on the Protocol keeps one Protocol equal to one course. That
matters for the Effect view, which compares outcomes before, during and after a
Protocol. A stack that mixes a cycling Compound, a time-limited course and
ongoing Compounds is modeled as one Protocol per rhythm. For the example user
that is "Skin" for GHK-Cu, "Shoulder" for BPC-157, and "Daily" for the rest. A
Compound can still sit in several Protocols, and its planned doses for a day
are the sum across them.

How a date is decided for one Protocol and Protocol Member, in order:

1.  outside the Protocol's bounds → `outside`;
2.  paused → `paused`;
3.  in a cycle's off-period → `off_cycle`;
4.  the Protocol was archived before the date, or no member row of the
    Compound covers the date (it was removed earlier, or not yet added) →
    `removed`;
5.  otherwise the member's Schedule Version for that date decides:
    *   no version, or an `unscheduled` rule → `no_schedule`;
    *   `as_needed` → `as_needed`;
    *   a rule whose days exclude the date → `not_scheduled_today`;
    *   otherwise → `planned`, with its times or untimed count.

### D5. Reminders are a device-local reconciler over `flutter_local_notifications`

*   **Library:** `flutter_local_notifications`, with `timezone` and
    `flutter_timezone` to schedule wall-clock times in the phone's own zone. The
    plugin is initialized with every permission request turned off, so it never
    asks at startup. The rest timer keeps its existing native channel unchanged.
    *   **An unknown zone id.** When the bundled timezone database lacks the
        id the phone reports (a vendor-specific or newly added name), the
        reconciler uses a fixed zone at the phone's current offset, named
        after that offset. Today's wall times stay right; only a
        daylight-saving change inside the horizon is missed, until a run
        after it. Without the fallback, every run would throw and schedule
        nothing. (Settled after Phase 5's build.)
*   **iOS routing.** `AppDelegate.swift` is the notification center's
    delegate, and it answers every notification itself. Nothing is forwarded
    to `super`, so the plugin never receives a tap or a foreground
    presentation. In `didReceive`, a notification whose `userInfo["timerId"]`
    is present keeps today's timer handling; one whose plugin payload has
    kind `protocolReminder` is sent to Dart as a reminder tap (see **Tap**);
    any other is ignored. In `willPresent`, a reminder that fires while the
    app is in the foreground shows as a banner and in the notification list
    (`[.banner, .list]`), and every other notification keeps the timer's
    banner only (file 53). (Phase 5 follows file 53; this bullet said
    non-timer notifications were forwarded to `super`, which file 53
    contradicted. Settled after Phase 5's build.)
*   **Android:** inexact delivery (`inexactAllowWhileIdle`), with no
    exact-alarm permission. Delivery is usually within minutes, and up to about
    an hour late under Doze or battery saver. Exact alarms need a user-granted
    permission and a Play policy declaration, so they are a follow-up. The
    plugin's receivers are registered for boot and app updates.
*   **One notification per planned time.** Every planned dose due at that
    minute shares it. Each reminder's id is derived from its date and time
    (formula in file 48), so re-running the reconciler replaces rather than
    duplicates. Reminder ids are negative, and the timer's ids are
    non-negative, so the two never collide.
*   **Text is always generic:** title "Supplements", body "Planned for
    9:00 AM". This holds whether or not the lock is on, so turning the lock on
    later can't leave named reminders queued. Android notifications are
    `VISIBILITY_PRIVATE`, and the channel is named "Reminders". The time is
    formatted with `DateFormat.jm()` in the phone's language, as the day's
    Dose rows are, so in `en_US` a narrow no-break space comes before
    "AM" or "PM". (Settled after Phase 5's build.)
*   **What gets a reminder.** The reconciler's input is a list of
    `{protocolId, compoundId, localDate, localTime, remindersEnabled, filled}`,
    one per timed planned dose, from the Protocol Plan core. A time gets a
    reminder only if at least one unfilled timed planned dose at that time
    belongs to a Protocol with reminders on. Past times never do, and untimed
    planned doses never do.
    *   **The archive day.** A Protocol or member archived today still gets
        reminders for today's later planned times, because the archive day
        itself is still planned (D1), and nothing here overrides that. Its
        reminders stop from the next day. (Settled after Phase 5's build.)
    *   **Daylight-saving changes.** A planned time that a spring-forward
        change skips fires at the first valid minute after the gap, so
        02:30 fires at 03:00. Distinct planned times inside one gap keep
        their own reminders, because each (date, time) has its own id, so
        they fire together at that minute. A time that a fall-back change
        repeats fires once, at its first occurrence. (Settled after Phase
        5's build.)
*   **When it runs.** On app start, on resume, after any change to Protocols,
    Schedules or Doses (debounced 500 ms), and after sync completes. It also
    runs when the reminder status screen opens and when its device switch
    is flipped (file 58), so the screen shows a fresh status. There are
    no background or timezone-change triggers: travel takes effect on the next
    open or resume (CUJ 8).
*   **One run at a time.** A trigger during a run marks the reconciler dirty,
    and exactly one more run follows. The logging path never waits for it.
    A run that fails part way, such as when the plugin's pending list can't
    be read, changes nothing: what was pending stays pending, and the next
    trigger tries again. (Settled after Phase 5's build.)
*   **Rescheduling everything.** A pending reminder's id says its date and
    time, but not the zone it was scheduled in, so a pending reminder from
    another zone can't be told apart from a current one. The first run in
    each process, and any run after the phone's zone has changed, therefore
    schedules every wanted reminder again, each replacing the pending one
    with its id. Other runs schedule only the reminders missing from the
    pending list. (Settled after Phase 5's build.)
*   **Cancelling.** It cancels only notifications whose payload kind is
    `protocolReminder`, and never calls `cancelAll`. When the device switch is
    off, no Protocol has reminders on, or the notification permission isn't
    granted, it cancels all of its own notifications and schedules none.
*   **The scheduling horizon** is `min(14 days, as many days as fit in 48
    pending notifications)`. That leaves 16 of iOS's 64 pending notifications
    for the rest timer, which uses 2 per timer. The Protocol screen shows the
    resulting date next to the Reminders switch (CUJ 11).
    *   **Its days.** The 14 days are today through today + 13, with today
        read in the phone's current zone. If today's own reminders already
        exceed 48, nothing is scheduled, and the horizon's end is yesterday.
        One horizon covers every Protocol, so "Reminders scheduled through
        <date>" is the same date on every Protocol screen and on the status
        screen. (Settled after Phase 5's build.)
*   **Moving a time earlier.** When a same-day edit moves a time to one that
    has already passed, today gets no reminder at that time (CUJ 6). This is
    accepted.
*   **Per device:** a local "Reminders on this device" setting, default on,
    stored in the device-level `settings.json` and never synced. What is
    pending, what fired and what was tapped is never synced and never written
    to the Activity Log.
*   **Permission** is requested when the user first turns reminders on for a
    Protocol, never at onboarding (CUJ 10). Reminders reuse the rest timer's
    existing request, `TimerBackgroundScheduler.requestPermissionIfNeeded()`,
    and its `TimerBackgroundPermissionStatus`: both ask for the same system
    notification permission, so there is one permission path, not two. A new
    read-only `notificationPermissionStatus()` on the same channel reports the
    state, including "not asked yet", without prompting (file 51). On a device where any Protocol has
    reminders on and the device switch is on, but permission was never asked
    for, the Protocol Day view shows a banner that requests it (CUJ 12).
    *   **"The first time"** (CUJ 10) means `notificationPermissionStatus()`
        reads `notDetermined` when the switch turns on. Any other answer,
        or a read that fails, asks nothing. (Settled after Phase 5's
        build.)
    *   **"A Protocol has reminders on"** (CUJ 12 and the status screen)
        means a Protocol that isn't archived has its Reminders switch on,
        or a reminders-on timed planned dose still falls in the horizon (a
        Protocol archived today keeps today's). It is read from the
        Protocols themselves, not only from the horizon, so the banner
        shows even when none of that Protocol's timed doses falls in the
        next 14 days. (Settled after Phase 5's build.)
*   **Tap:** the payload carries only `{kind: "protocolReminder", localDate}`.
    On iOS, `AppDelegate` handles a reminder tap itself and sends
    `onProtocolReminderTapped(localDate)` over the existing
    `perennia/timer_background` channel, reusing its cold-start buffering. On
    Android the plugin's own tap callback delivers it.
    The app opens through `ProtocolsLockGate`, the widget that shows the PIN or
    biometric prompt when the lock is on, to that date's Protocol Day. When
    the Protocol Day view is already on top, a tap only selects its date
    and pushes nothing, as a rest-timer tap for the exercise already on top
    opens nothing. (Settled after Phase 5's build.)

### D6. Matching, statuses, the Planned list and the Agent surface

**Matching**, for one Compound on one local date:

1.  **Collect the planned doses.** Take every planned dose from every Protocol
    in effect containing the Compound. Number them `slot` 0..n-1, ordered by
    time (untimed last), then Protocol id, then position.
2.  **Collect the logged Doses.** Take every non-archived Dose of the Compound
    with that `localDate`, tagged or not, ordered by local time and then id.
    UUIDv7 ids sort by creation time, so `sequence` is the index in this order.
3.  **Fill the slots.** Take each Dose in that order. It fills the unfilled
    timed slot nearest to its time; on a tie, the earlier slot. If no timed
    slot is unfilled, it fills the first unfilled untimed slot. If nothing is
    unfilled, the Dose is an extra.
4.  **Report every slot.** `fills` lists every slot, with `doseId: null` when
    it is unfilled.

**Counts.** `plannedCount` is the number of slots. `loggedCount` is the
number of filled slots, not the number of Doses, so it never exceeds
`plannedCount`. `extraCount` is the number of Doses that filled nothing. So
`loggedCount + extraCount` is the number of Doses on that Compound and date.

**Doses with no PlanDay.** A Day Status exists only for a Compound and date
that has at least one PlanDay in the input. A Dose whose Compound and date
has none is ignored. That happens for a Compound in no Protocol, or one
filtered out by the caller. It is not counted as an extra anywhere. A Compound
in no Protocol therefore has no Day Statuses. Its Consistency view (Phase 4)
lists those Doses by date without a status label.

Filling by nearest time means a Dose at 20:50 fills a 21:00 slot, not an
unfilled 09:00 one. So the 21:00 reminder doesn't fire after the Dose, and the
morning reads "Not logged", which is what happened. The same rule can
surprise when a Dose is logged from the Planned list at the current time:
it may fill a later slot than the row that was tapped. This is accepted
(see Open Questions). The Protocol tag only
records which Protocol a Dose was logged under; it never decides whether the
Dose counts. A Template Link works the same way in Training: it records
provenance, never adherence.

**Day Status**, one per Compound per date, decided in this order:

*   **When the Compound has planned doses that day** (`plannedCount > 0`,
    summed across Protocols in effect):
    *   today: "Logged" when logged ≥ planned, else "Pending";
    *   a past day: "Logged" when logged ≥ planned, "Partly logged" when
        0 < logged < planned, "Not logged" when nothing is logged.
*   **When it has none** (`plannedCount = 0`):
    *   "Paused" if any Protocol reports `paused`;
    *   otherwise "Off cycle" if any reports `off_cycle`;
    *   otherwise "Not planned", with a `notPlannedReason` taken in this order:
        1.  `not_scheduled_today`;
        2.  `as_needed`;
        3.  `no_schedule`;
        4.  `removed`;
        5.  `outside`.
*   **Dates after today** have no Day Status.

Each status has a text label; color is never the only signal. Extra Doses are
counted next to the status and never change it. UI copy and API fields never
use "missed", "late", "overdue", "adherence", "streak", or a percentage.

**Amounts.** The Consistency view shows the planned amount next to each logged
amount, each as entered. When both resolve to an active mass, it also shows
both masses. Active mass is the amount times the Compound's strength, so 0.1 mL
of a 20 mg/mL Compound is 2 mg; it is computed by `resolveDoseActiveMass` in
`apps/mobile/lib/domain/protocols/protocols.dart`. There is no verdict. The UI
computes this from the Dose and the slot; the core has no field for it.

*   **Which strength.** The planned mass uses the Compound's current
    strength, because a Schedule Version stores an amount and unit but no
    strength. The logged mass uses the strength frozen on the Dose when it
    was logged (its snapshot), so a later change to the Compound never
    rewrites what was taken. After a strength change, a past day's two
    masses can therefore differ while both amounts as entered match; the
    amounts as entered stay the primary reading. Both masses show only
    when both resolve. (Settled after Phase 4's build.)

**The Planned list** sits at the top of the Protocol Day view, inside the lock.
It is hidden when the day has nothing planned. It has no heading of its own:
its Protocol group headers and row labels say what it is.

*   **Rows.** Each row is one slot, grouped under its slot's Protocol. It shows
    the Compound, the planned time (or "Any time"), the amount, and one label:
    "Logged" when filled, "Pending" when unfilled today, "Not logged" when
    unfilled on a past day. Groups are ordered by Protocol name, then id.
    Within a group, rows are ordered by planned time (untimed last), then
    Compound name, then Compound id, then slot.
*   **Tapping a "Pending" or "Not logged" row** opens the log sheet
    prefilled with the planned amount and route, tagged with the row's
    Protocol. On today, the time is now. On a past day, it is the row's
    planned time on that date, or 12:00 for an untimed row. Both date and
    time are editable.
*   **Tapping a "Logged" row** opens the Dose that fills it (its `doseId` in
    `fills`) for edit, as tapping that Dose in the day's log does. A new log
    from a filled row would record a second Dose of something already
    taken, which is the duplicate the row exists to prevent. An extra Dose
    is still logged from the Compound list. (Phase 3 opens a new log here,
    reading the old wording "tapping a row" literally; file 40a changes it.)
    *   **How the row finds its Dose.** `PlannedRow` carries no `doseId`.
        The view finds the row's fill in the `PlannedDay`'s Day Statuses,
        by the row's Compound, Protocol and slot, and then the Dose with
        that fill's `doseId` in the same emission's `ProtocolDayRecord`.
        Both come from one read, so a filled slot's Dose is always there.
        If it were missing, tapping the row would do nothing rather than
        start a new log. (Settled after file 40a's build.)
*   **"Log all planned"** appears only on today's Protocol Day, while at
    least one row reads "Pending". It logs every due unfilled planned dose:
    timed ones whose time is at or before now, and untimed ones. Each is
    timed now and tagged with its row's Protocol. All are written in one
    transaction and one Batch (`dueUnfilled` in the core picks the rows).
    Past days have no bulk action.
    *   The button follows the labels the user sees, not what is due, so
        it doesn't appear and disappear as planned times pass. Before the
        first planned time (07:00 with everything planned for 09:00), a
        tap finds nothing due, writes nothing and shows nothing.
    *   It reads today's stored plan when tapped, not the rendered rows.
    *   It can't log twice: the button is disabled while its write runs,
        and a second call made before the first finishes shares the first
        call's result instead of reading the plan again.
    *   A write that fails shows no message, the same as the log sheet's
        Save; showing one needs new copy.
*   **The day boundary.** "Today" is read when the day is built, and the
    view rebuilds when local midnight has passed, checked once a minute
    and on resume. Without it, a view left open overnight would keep
    yesterday's "Pending" rows and its "Log all planned" button. The
    selected Protocol Day stays where it was: the day that was today now
    reads as a past day.
*   **The log sheet** gains a date field (CUJ 7). The date and the time are
    stacked as two full-width rows, each a 48 dp target that opens its
    picker, rather than side by side.
    *   Opened outside the Planned list, it defaults to now on today, or
        12:00 on a past Protocol Day, and the amount still prefills from
        the last Dose of that Compound. It no longer prefills the time from
        the last Dose; that default recorded times that never happened.
    *   A future Protocol Day (reached from the Compound list, file 38) is
        treated as today: the time defaults to now, never to a moment that
        hasn't happened.
    *   The date picker ends at today, or at the edited Dose's own date
        when that is later, so it never offers a day still to come. On an
        edit of a Dose with a frozen offset, "today" is read at that
        offset, the frame its fields show; otherwise in the device's zone.
        Read in the device's zone, a Dose logged far from it could be
        moved to a day that hasn't happened where it was taken, or kept
        from one that has. (Settled after file 40a's build.) That "today"
        reads the clock through the same helper as the Dose's own fields
        (`clockAtOffset`, file 46a), so the picker and the fields can't
        disagree. (Settled after file 46a's build.)
    *   When an existing Dose is edited, the sheet shows its date and time
        at its frozen `timezoneOffsetMinutes` (D2), in the device's zone
        only when the offset is null. Its date and time may change. A
        changed date or time is read at that same offset, which the Dose
        keeps, and its local date is frozen again from the new time. An
        edit corrects when the Dose was taken where it was taken; reading
        the change in the device's current zone would move a Dose logged
        abroad by the difference between the two zones. An untouched Save
        changes neither. (Phase 3 shows and reads the time in the device's
        current zone; file 40a changes it.)
        *   **Where the offset is applied.** The sheet holds the date and
            time as a clock reading at the Dose's offset, and turns it into
            the moment only on Save. When the moment changed, it sends no
            `localDate` and no `timezone`, and `editDose` keeps the offset
            and the timezone label and freezes the local date from the new
            moment at that offset. A draft that names its own `localDate`
            or `timezone` still takes precedence, as it does on any edit.
            (Settled after file 40a's build.)
*   **The day's Dose rows**, below the Planned list, show each Dose's time
    at its own frozen offset, as its edit sheet does (D2). Phase 3 orders
    them by instant, then id. On a Protocol Day that holds Doses logged at
    different offsets, their clock times can then read out of order, and
    the order differs from matching's (local time, then id; step 2). File
    46a orders them by clock instead.
    *   **What "clock order" is.** The rows sort by each Dose's clock where
        it was taken (`DoseRecord.clock`), date and time to the minute,
        then id. The clock's date leads. When every Dose's clock falls on
        the Protocol Day, that is matching's order, so the day's log and
        the Planned list take the day's Doses in the same order. A Dose can
        be filed under a date its clock doesn't fall on: its draft named
        its own `localDate`, or it has no offset and is read in a device
        zone it wasn't logged in. That Dose stays in clock order, and there
        the two orders can differ. Sorting by time of day alone, as
        matching does, would list 08:00 the next morning before 17:00 the
        day before. (Settled after file 46a's build.)
    *   **Matching is unchanged.** It still numbers a Compound's Doses on a
        date by time of day (`HH:MM`), then id, as step 2 and the m36
        vectors define. (Settled after file 46a's build.)
*   **A future Protocol Day** shows its Planned list with times and amounts,
    but no log action and no status label.
*   **Day Status labels.** Phase 3 adds the strings for the seven Day
    Statuses and the five not-planned reasons, but the Planned list shows
    only its three row labels. Phase 4's Consistency view is the first
    surface to show the others.

**The Consistency view** opens from a Compound's row in the Compound list, or
from a Protocol, where it shows a tab per member. For a date range (default:
the last 30 days, including today), it shows a chart of each Dose's time of day
against the planned times, built with `fl_chart` like the existing Effect
timeline. Below the chart is a day-by-day list of Day Statuses, times and
amounts. Building Phase 4 settled the rest:

*   **The range.** The presets are the last 7, 30, 90 or 365 days, each
    ending today. A custom range ends at today at the latest, because the
    view never shows a day still to come, and its picker starts at
    2000-01-01. A custom pick longer than 366 days keeps its last 366, and
    the dates written out under the picker show the range actually read.
    "Today" is read from the Protocols clock (file 37) when the view opens
    and on every pick. One range serves every tab.
*   **The day boundary.** Unlike the Planned list, the view doesn't
    rebuild when local midnight passes. It has no log action, so a stale
    "today" can't date a Dose. A view left open past midnight keeps its
    range, where the old today's unfilled slots still read "Pending",
    until a range is picked or the view is opened again.
*   **Tabs.** Opened from a Protocol, the view has one tab per member, in
    member order. Each tab is that member Compound's own Consistency
    across every Protocol it is in, not only the one it was opened from,
    because a Day Status is one per Compound and date, summed across the
    Protocols in effect. Each tab is named by its own read, so an archived
    Compound keeps its name. The Protocol's button shows only on a saved
    Protocol with members, and the tabs are its members as saved, not the
    form's unsaved edits; a new Protocol has nothing stored to show. The
    selected tab reads in the primary text color over an indicator of the
    same color, and the others in the secondary text color: the theme's
    default tab color, the brand primary, fails WCAG AA on the light
    chrome.
*   **The lock.** From both entry points, the view sits inside its own
    `ProtocolsLockGate`, so if the app locks while it is on top, it is
    covered like the rest of the section.
*   **The chart.** Each logged Dose is a dot at its frozen local date and
    time. A Dose that filled nothing is a ring instead of a filled dot;
    the chart reads which Doses are extras from the day list's own
    extras, so the two never disagree. Each planned time is a horizontal
    segment over the run of consecutive days it is planned on, so a
    Schedule Version change moves the line on the day it applies from;
    two Protocols planning the same time on a day draw one segment.
    Untimed planned doses are segments in an "Any time" band above the
    day.
*   **Shading.** Paused and off-cycle days, by their Day Status, are
    shaded runs. Both use one shade and differ by pattern: off-cycle runs
    are hatched. Every run, however short, gets a marker under the plot,
    solid for paused and dashed for off cycle, in the secondary text
    token, which keeps its contrast in both themes. A run at least 56 px
    wide also gets its word, "Paused" or "Off cycle", under its marker.
    The legend names both shadings with the same patterns, and the day
    list labels every day. So a one-day run with no room for its word is
    still told apart without color. A day after today has no Day Status,
    so it is never shaded.
*   **The day list** is newest date first. For a Compound in a Protocol,
    it lists every date of the range, each with its Day Status; a date
    with no Day Status is listed only when it holds a Dose. Each date
    shows its label, the not-planned reason, and the extra count next to
    them. Each slot shows its planned time (or "Any time"), its amount and
    the name of its Protocol, then the Dose that filled it, or "Pending"
    on today and "Not logged" before it. The extra Doses follow, marked
    "Extra". A Compound in no Protocol shows a line saying it has no Day
    Statuses, then its Doses by date with no label. The read returns the
    range's Doses sorted by frozen `localDate` first, then each date's in
    the day log's clock order ("The day's Dose rows"), so a date's Doses
    and extras read as that day's log does. (Settled after file 46a's
    build.)

**The Effect view.** Its window input moves to `effectBoundsFromLocalDates`
(D2); its math is unchanged. For a Protocol with a cycle or Pauses, it shows
"Off-cycle and paused days are counted as during."

**The "N doses" helper** (`endDateForDoseCount`, Dart only):

*   **What it returns:** the local date of the Nth planned dose of one member,
    counted from the Protocol's start. It counts doses, not days: a rule of
    08:00 and 20:00 reaches 20 doses on day 10. It skips off-cycle and paused
    days, and uses the member's current rule.
*   **Limits:** N is 1 to 1000; outside that range it throws a `RangeError`.
*   **"Unavailable"** is `null`. It is returned for an `as_needed` or
    `unscheduled` rule, for a rule that is never on (its days never fall on
    an on-cycle day), and when the Nth dose would fall after 9999-12-31, the
    last date a `YYYY-MM-DD` value can hold. It stops there rather than
    walking on.
*   **Inputs:** named parameters `startLocalDate`, `rule`, `doseCount` and an
    optional `period`. The Protocol's end date is not an input: this
    computes it.
*   **Why Dart only:** no Agent operation uses it.

**Contract changes for the Agent surface:**

*   **Naming.** Agent fields are camelCase, like the rest of the Agent API:
    `startLocalDate`, `endLocalDate`, `period`, `remindersEnabled`,
    `effectiveFrom`, `rule`, `timezoneOffsetMinutes`, `archivedOn`, `today`.
    Snake_case stays in Drift columns and sync payloads. Two more naming
    rules hold at the Agent surface:
    *   **Inside `rule` and `period`, keys stay snake_case.** Their keys
        (`on_days`, `anchor_is_default`, `every_n_days` and so on) are the
        stored JSON of the Data shapes, which the codecs, validators and vectors all
        read. An Agent reads and writes that same document. Renaming its
        keys at the API would need a second codec in each language, which
        the vectors would then have to pin too.
    *   **The Schedule's amount fields** keep their existing Agent names,
        `doseAmountValue`, `doseAmountEntered`, `doseUnit` and `route`,
        rather than the core's `amountValue`, `amountEntered` and `unit`.
        They are the fields Agents already write, and renaming them would
        break Agent clients for no gain.
*   **Same release as the app.**
    *   Protocol and Schedule reads and writes carry the new fields, validated
        by the shared two-tier module (D7).
    *   `frequency` is removed from Agent Schedule writes; a write that
        includes it is rejected.
    *   The Protocol batch write carries a required top-level `today`, the
        user's local date, as the Day Status read does. It is the one Agent
        write that dates something by the user's calendar: a version's
        `effectiveFrom` and an archive's `archivedOn`. A Dose carries its
        own local date: `localDate` is a required field of each Dose, stored
        as sent. Nothing checks that it is a real date or that it agrees
        with `tookAt` and its offset. No other batch write reads a local
        date, so no other write carries `today`; requiring it there would
        break every Agent client for a field nothing reads.
        The server assigns
        `effectiveFrom` exactly as the app does (D1). A write can't set `effectiveFrom` itself, can't reuse
        an existing version id, and can't archive a version, so versions are
        insert-only for Agents as they are for the app.
    *   **A Schedule entry is an explicit edit.** The editor sends every
        member's Schedule on every save, so the app drops unchanged ones
        (D1). An Agent sends only the Schedules it means to change, each
        under a new id, so the server inserts every Schedule Version the
        write carries, even one equal to the current version. Dropping it
        would leave the id the Agent chose, and the response reports,
        pointing at nothing. An equal version plans exactly what its
        predecessor planned, so inserting it changes no Day Status.
    *   **Start moves** make the same copies as the app (D1), from the rows
        and versions stored before the request, inside the write's
        transaction.
    *   **A Protocol write replaces the whole row.** Every field of the
        Protocol is written as sent. A field left out takes its default:
        `endLocalDate` and `period` become null, and `remindersEnabled`
        false. The schema's description says so, and tells an Agent to send
        every field as read to change one. A patch was rejected because it
        would have to tell "left out" from "set to null" for `endLocalDate`
        and `period`, where null is a real value (ongoing, no cycle and no
        Pause). Members, Schedule Versions and target outcomes are separate
        rows, and a write changes only the ones it lists.
    *   An Agent archives a Protocol Member or a Protocol by sending
        `archived: true`; their write schemas no longer accept `deletedAt`.
        A target outcome is not part of this change: its write schema is
        not strict and still takes `deletedAt`, and the Agent skill's
        reference archives an outcome by setting it (file 29). The
        server stamps `deletedAt` with the current time and sets `archivedOn`
        to `today`. So an Agent can't
        backdate a removal, just as the app can't.
        *   Re-sending `archived: true` for a member that is already archived
            is accepted and keeps its first stamp, so a write may list every
            member of the Protocol, removed ones included.
        *   `archived: false` (or leaving it out) for a member that is
            already archived is refused with `archived_row_not_restorable`.
            No path restores an archived row (D1).
        *   A write that names an archived Protocol is refused with
            `protocol_archived`, whatever it sends, because the app can't
            edit an archived Protocol either (D1). "Archived" means the
            stored row has both `deleted_at` and `archived_on`.
        *   A write that names a Protocol tombstoned by undo (`deleted_at`
            with no `archived_on`) is refused with
            `archived_row_not_restorable`, whatever `archived` it sends.
            Undo means the row never existed (D1), so it isn't "archived",
            but it can't be edited either: a re-sent `archived: true` must
            not change its fields or move its start.
        *   A refused Protocol gets no start-move copies. The write's
            member and Schedule checks still run beside the refusal, so one
            response lists every problem: `archived: false` on an archived
            member, say, or a Schedule naming no member. A write that
            re-sends the Protocol's members with `archived: true` and no
            Schedules reports only the Protocol's refusal.
        *   A member tombstoned by undo and sent with `archived: true` is
            accepted as Phase 2 built it. It keeps its stamp and its null
            `archived_on`, so it stays a tombstone that every reader
            ignores.
        *   Reads don't carry an `archived` field. `archivedOn` is non-null
            exactly when the row is archived, and is the one place that says
            so. A read is not a write shape anyway: `versions`,
            `currentVersion`, `archivedOn` and `deletedAt` are all refused
            by the strict write schemas.
        *   Reads leave out a Protocol or member tombstoned by undo, even
            with `includeArchived`, because it never existed (D1).
        *   The read schema keeps `startLocalDate` nullable. The server reads
            the stored payload as it is, and a row synced before Phase 2 can
            lack the field; failing the whole list on one such row would
            hide every other Protocol. A row the app writes always has it.
    *   `today` must be within one day of the server's UTC date, which every
        real timezone satisfies; otherwise the write is rejected. This keeps
        an Agent from writing something a person using the app could not.
    *   Dose writes gain an optional `timezoneOffsetMinutes` (D2).
    *   The Effect read gains an optional `timezoneOffsetMinutes` (D2).
*   **Agent write issues.** A refused Protocol write returns 422 with one
    issue per problem, each with a stable `rule` id. The D7 check ids pass
    through unchanged. The write path adds these:

    | Rule id | When |
    | :------ | :--- |
    | `today_out_of_range` | `today` is more than one day from the server's UTC date (field `today`) |
    | `schedule_version_exists` | a Schedule id already exists for this account: versions are insert-only |
    | `schedule_member_not_found` | a Schedule's `protocolCompoundId` is not a member of the Protocol it is listed under, in this request or already stored (a row tombstoned by undo doesn't count) |
    | `archived_row_not_restorable` | `archived: false`, or no `archived`, for a member that is already archived; or any write naming a Protocol tombstoned by undo |
    | `protocol_archived` | the write names a Protocol that is already archived (file 34a); one tombstoned by undo gets `archived_row_not_restorable` instead |
    | `rule_format`, `period_format` | the codec refuses a `rule` or `period` the D7 validators accepted. Unreachable while the two agree; it is a guard so a drift between them refuses the write instead of storing a row no reader can plan |

    An accepted write that drew soft warnings (such as `times_many`) returns
    them in a top-level `warnings` array beside `protocols`. A refused write
    returns its `warnings` beside its `errors`.
*   **Later stage.** Two new reads, mirrored as MCP tools:
    *   `listAgentProtocolPlannedDays`: `GET /agent/protocols/planned-days`, MCP
        tool `agent_list_protocol_planned_days`.
        *   Parameters: `fromLocalDate` and `toLocalDate` (inclusive, at most
            366 days apart; future dates allowed), plus optional `compoundId`
            and `protocolId`.
        *   Returns the `PlanDay` records of the core API, in the envelope
            `{fromLocalDate, toLocalDate, plannedDays}`. Each entry of
            `plannedDays` is `{protocolId, compoundId, localDate, state, planned}`:
            one per Protocol, Compound with a member row in it, and date,
            ordered by date, then Protocol id, then Compound id. `planned`
            is non-empty exactly when `state` is `planned`, in the rule's
            stored order. Each planned dose is
            `{localTime, amountValue, amountEntered, unit, route}`.
            `localTime` is null for an untimed dose. The four amount fields
            are always present, and null when unset. They keep the core's
            names, not the Schedule's Agent names (`doseAmountValue` and so
            on, under Naming above), because this read returns the core's
            records. (Settled after Phase 6's build.)
    *   `listAgentProtocolDayStatuses`: `GET /agent/protocols/day-statuses`, MCP
        tool `agent_list_protocol_day_statuses`.
        *   Parameters: the same as the first, plus a required `today` and
            `detail=summary|doses`, default `summary`. `toLocalDate` must not
            be after `today`.
        *   With `summary`, returns
            `{compoundId, localDate, status, notPlannedReason?, plannedCount, loggedCount, extraCount}`.
            With `doses`, it also returns `fills`.
        *   **Its envelope** is
            `{fromLocalDate, toLocalDate, today, detail, dayStatuses}`,
            echoing the query, with `detail` at its default when left out.
            `dayStatuses` holds one Day Status per Compound and date that
            has at least one planned day in the plan read, ordered by
            date, then Compound id. A Compound in no Protocol read has
            none. `notPlannedReason` is present only when `status` is
            `not_planned`. `fills` is present only with `detail=doses`:
            every slot, in slot order, as
            `{slot, protocolId, plannedLocalTime, amountValue, amountEntered, unit, route, doseId}`,
            with `doseId` null for an unfilled slot and the amount fields
            as in the planned-day read. (Settled after Phase 6's build.)
        *   **With `protocolId`, it reads one Protocol's plan.** The read
            plans only that Protocol (file 61) and matches the Compound's
            Doses against its planned doses alone. Doses are never filtered
            by Protocol, because a Dose's tag never decides what it fills
            (step 2). So for a Compound that is also in another Protocol,
            the answer can differ from the app's Day Status, which sums
            every Protocol in effect. Say Protocol A plans the Compound at
            09:00 and Protocol B at 21:00, and one Dose is logged at 20:50
            on a past day. The app fills B's 21:00 slot and shows "Partly
            logged". With A's `protocolId`, the read has only the 09:00
            slot, the Dose fills it, and the day reads `logged`. The app
            has no Day Status for one Protocol, so an Agent that needs the
            app's answer for a Compound filters by `compoundId` and leaves
            `protocolId` out. The schema's description says so. (Recorded
            as built after Phase 6's build.)
    *   **Response enums** are the core's `PlanDayState`, `DayStatusValue`
        and `NotPlannedReason`, checked against them at compile time both
        ways. A value added to the core stops the server compiling, rather
        than the response schema refusing the core's output with a 500.
        (Settled after Phase 6's build.)
    *   Errors: 400 for a range over 366 days, for `fromLocalDate` after
        `toLocalDate`, and for `toLocalDate` after `today`. Unknown ids return
        an empty list. Building Phase 6 settled the rest:
        *   **The range counts both ends**, as the Consistency view counts
            it (file 44): 2026-01-01 to 2026-12-31 is 365 days, and the
            most either read takes is 366.
        *   **`today` is bounded on the Day Status read too.** It must be
            within one day of the server's UTC date, the bound the Protocol
            batch write puts on its `today` (above), with the same message;
            one check serves both. Every real UTC offset puts the user's
            date there (D2). Without the bound, a `today` a year ahead
            would read every planned day before it as Not logged, which no
            person using the app could see.
        *   **The 400 body** for these checks is
            `{code: "agent_protocol_days_invalid_request", message}`. REST
            and MCP run the same checks, through one function, before any
            storage read; MCP returns the same body as an error result. In
            order: `fromLocalDate` after `toLocalDate`, the range, the
            `today` bound, then `toLocalDate` after `today`.
        *   **A query the request schema refuses**, such as a date that
            isn't a real `YYYY-MM-DD` date or a missing `today`, is
            answered 400 before authentication, with the request
            validator's own error body, as on every other route. The route
            descriptions say so.
        *   (Settled after Phase 6's build.)
    *   **Rows the reads can't use** are skipped rather than failing the
        read, as the Protocol list read skips them (Reads, below):
        *   a Protocol with no readable start date plans nothing;
        *   a Schedule Version whose `effectiveFrom` or rule the codec
            can't read is left out, and a period it can't read reads as
            none;
        *   a Dose with no readable Compound id, local date or `tookAt`
            fills nothing.

        A Protocol Member plans only while the user holds a row for its
        Compound, archived or not, because the app's plan query inner-joins
        `compounds`. A member synced before its Compound plans nothing in
        either until the Compound arrives. (Settled after Phase 6's build.)
*   **Reads** return each Protocol Member's full version history as
    `versions`, sorted by `effectiveFrom` and then id, plus `currentVersion`,
    the version the editor would show (the latest `effectiveFrom`, then the
    larger id). Versions tombstoned by undo are left out. A version whose
    `effectiveFrom` or `rule` the codec can't read, and a `period` it can't
    read, are left out too (the period reads null), rather than failing the
    whole read. No writer of this version can store one, because both
    writers validate and encode through the codecs. Such a row could only
    come from a later rule version (`v` 2), which this read can't plan from
    either.
*   **The contract diff.** It shows these field and route changes in
    `packages/contract/openapi.json` and the generated clients. Responses
    carry statuses and counts only, with no ratio or streak field.

### D7. Validation

Plan values join the shared two-tier validation module.

*   **Where the checks live.** Dart adds
    `apps/mobile/lib/domain/protocols/protocol_plan_validation.dart`, following
    the file layout of `apps/mobile/lib/domain/training/plan_validation.dart`.
    TypeScript extends `apps/server/src/agent-validation.ts`, where that file's
    twin also lives.
*   **Limits.** The numeric limits below live in a `ProtocolPlanValidationLimits`
    class in Dart and a `PROTOCOL_PLAN_VALIDATION_LIMITS` constant in
    TypeScript. Both are defined in the core files (`protocol_plan.dart`,
    `protocol-plan.ts`), whose decoders enforce the ceilings, and the
    validation modules re-export them. The vector file carries a matching
    `limits` block, and both runners assert it, as the precedent's runners
    do.
*   **Result type.** Results use the Dose validator's issue type, because it
    is the Protocols domain's own: `DoseValidationIssue` in Dart and
    `AgentDoseValidationIssueSchema` in TypeScript. That gives errors and
    warnings whose `rule` field is the stable id of a check below.
*   **Signatures.** `validateScheduleRule(rule, {amountValue, amountEntered,
    unit, route})` and `validateProtocolPeriod({startLocalDate, endLocalDate,
    period})`, with the same parameters in both languages.
*   **What they read.** `rule` and `period` are the stored JSON (a map, or
    null for no period), not decoded values, so the validators can judge
    values the codecs reject: a time of "9:00", an anchor of "2026-02-30", a
    count of 2.5. They assume a known `v` and `kind`; rejecting an unknown one
    is the codec's job. A whole number written as a float (`2.0`) counts as
    that integer, because JSON can't tell them apart.
*   **Typed bounds.** `startLocalDate` and `endLocalDate` are real dates
    already: a `ProtocolDayDate` in Dart, and in TypeScript a `YYYY-MM-DD`
    string that must be a real date. A bound that isn't a real date is a
    caller bug and throws a `RangeError`; it is never reported as an issue.
    No date check is added for the bounds. The Agent write path rejects a
    non-date bound with 400 before calling the validator (file 29), and the
    app's date pickers can't produce one.
*   **Issue order.** Each check reports at most once, however many elements
    fail it: one `times_format` for three bad times, one `pause_overlap` for
    several overlapping Pauses. Errors come in the order of the table below,
    and so do warnings. Warnings are judged on their own, not only when there
    are no errors. So 13 times gives the error `times_count` and the warning
    `times_many`.
*   **`amount_required` in detail.** It applies to `timed` and `untimed` rules
    only. It requires all four fields: `amountValue`, a non-blank
    `amountEntered`, `unit` and `route`. Then the Dose validator
    (`validateDose` in Dart, `validateAgentDose` in TypeScript) judges
    `amountValue` with the unit and route, and any hard error it reports
    fails the check. `amountEntered` is the text as typed, kept for display,
    and is not judged further. The Dose validator's own rule ids are not
    passed through: every failure is reported once, as `amount_required`.
    Its soft warnings are dropped, because they belong to the Dose logged
    against the plan and show then.
*   **Order of times and weekdays.** Times and weekdays are stored sorted.
    Writers sort them: the app's `ProtocolsRepository` (file 21) and the
    Agent write path (file 29) sort both lists before inserting a version. The codecs and
    the validators accept any order, and no check judges it. `planDays` emits
    `planned` in stored order, and matching numbers slots by time anyway.
*   **Pauses with impossible dates.** A Pause whose `from` or `to` isn't a
    real date can't be ordered, so it fails `pause_order`. `pause_bounds` and
    `pause_overlap` skip that Pause.
*   **Vectors.** The same golden vectors run in Dart and TypeScript, and both
    runners compare `errorRules` and `warningRules` as ordered lists.

| Check id | Field | Condition | Tier | Function |
| :------- | :---- | :-------- | :--- | :------- |
| `times_format` | rule.times | each time is `HH:MM`, 00:00-23:59 | reject | `validateScheduleRule` |
| `times_count` | rule.times | 1 to 12 times | reject | `validateScheduleRule` |
| `times_distinct` | rule.times | no duplicates | reject | `validateScheduleRule` |
| `untimed_count` | rule.count | 1 to 12 | reject | `validateScheduleRule` |
| `weekdays_valid` | rule.days.weekdays | non-empty, each 1-7, no duplicates | reject | `validateScheduleRule` |
| `every_n_range` | rule.days.n | 2 to 365 | reject | `validateScheduleRule` |
| `anchor_date` | rule.days.anchor, period.cycle.anchor | a valid date | reject | both (each checks its own anchors) |
| `amount_required` | amount | for `timed` and `untimed`: all four of amountValue, amountEntered, unit and route present, and valid per the Dose validator (see above) | reject | `validateScheduleRule` |
| `amount_absent` | amount | for `as_needed` and `unscheduled`: all four of amountValue, amountEntered, unit and route null or absent (Phase 2) | reject | `validateScheduleRule` |
| `cycle_lengths` | period.cycle | on and off lengths each 1 to 3650 days | reject | `validateProtocolPeriod` |
| `bounds_order` | endLocalDate | not before startLocalDate (replaces `validateProtocolWindow`) | reject | `validateProtocolPeriod` |
| `pause_count` | period.pauses | at most 100 Pauses (Phase 2) | reject | `validateProtocolPeriod` |
| `pause_order` | period.pauses | each has real dates and from ≤ to | reject | `validateProtocolPeriod` |
| `pause_bounds` | period.pauses | within the Protocol's bounds | reject | `validateProtocolPeriod` |
| `pause_overlap` | period.pauses | no two overlap | reject | `validateProtocolPeriod` |
| `times_many` | rule.times | more than 6 a day, which is more often a typo than a plan | warn | `validateScheduleRule` |

**The two Phase 2 checks.** Phase 1 built every check above except
`amount_absent` and `pause_count`, which land in Phase 2 (file 17a).

*   **`amount_absent`** keeps the stored shape honest: the data shapes say
    the amount fields are null for `as_needed` and `unscheduled`. Without the
    check, an Agent could store an amount that nothing reads. The app's
    editor clears the amount when the user picks "As needed" or "No
    schedule".
*   **`pause_count`** bounds the Pause list, which a security review found
    unbounded. 100 is far beyond any real plan, and keeps a write's size and
    the overlap sort small. Its limit is `maxPauses` in the limits class, the
    constant and the vector's `limits` block. An over-long list reports only
    `pause_count`; the other Pause checks don't run on it.

**Issue fields.** Each issue carries the `field` and `limit` the Dose
validator's issues carry:

*   `amount_required`: field `amount`, limit `amount|unit|route`.
*   `amount_absent`: field `amount`, limit `absent`. "Absent" means null or
    missing. A blank `amountEntered` (`""` or spaces) is a value, so it is
    carried and rejects. `amount_required` reads blank as missing, because
    a planned amount needs text to show; `amount_absent` asks only whether
    the row stores anything, and a blank string is something.
*   `pause_count`: field `period.pauses`, limit `100` (`maxPauses`).

**In the app,** a rejected plan throws the same `DoseValidationException`
that a rejected Dose throws, carrying the shared issues, so the editor shows
both the same way. A negative planned amount is a hard reject of the Dose
validator, so it reports `amount_required`, like any other invalid amount.

Two checks sit outside the shared module, because only one side has what they
need. The "N doses" helper rejects N outside 1-1000; it is Dart only. Agent
writes that carry `today` must have it within one day of the server's UTC
date; that is the server's write path (D6).

## Alternatives Considered

### Alternative A: Remind when a Workout starts (D5)

*   **Pros**: Matches the cue several users rely on today ("before the gym").
    It is the one event the app can observe.
*   **Cons**: By the time a Workout starts in the app, the user has left the
    house without the dose. Waking, meals and bedtime can't be observed at all.
*   **Reason for Rejection**: It fires too late to prevent the forgotten dose,
    which is the problem being solved. Clock times are predictable, and the user
    can set them to match their daily habits.

### Alternative B: Generalize Protocols to habits and behaviors

*   **Pros**: One place for everything a user "follows": supplements, light
    exposure, mobility breaks.
*   **Cons**: A Dose is an amount, a unit and a route, so habits need a second
    kind of entry. A mobility session is already a Workout with a Routine plan.
    Protocols carry the strictest privacy rules in the app (the lock, the
    export exclusion), and those would apply to habits that don't need them.
    An open-ended habit list turns the feature into a general habit tracker.
*   **Reason for Rejection**: It splits one activity across two domains, and it
    extends the substance domain's privacy rules to data that doesn't need
    them. Protocols stay for substances.

### Alternative C: Log from the notification ("Log all as planned") (D5)

*   **Pros**: Logging takes one tap, without opening the app.
*   **Cons**:
    *   A double tap, a redelivered notification, a stale notification, or two
        devices each create separate Doses, which sync never merges. A
        duplicate TRT or GLP-1 Dose is a safety problem.
    *   It writes while the lock is on, about planned doses the user can't
        see.
    *   It needs a second database connection in a background engine, which
        tempts a write that skips validation and the Activity Log.
    *   "At tap time" records times that never happened.
*   **Reason for Rejection**: Deferred, not dropped. v1 opens the app instead,
    where "Log all planned" is one tap. The conditions for bringing it back are
    under Future Improvements.

### Alternative D: Follow-up reminders and a daily catch-up (D5)

*   **Pros**: A missed reminder gets a second chance.
*   **Cons**: Notification content is fixed when it is scheduled, days ahead,
    so a catch-up can't list what is outstanding at noon. A Dose logged on
    another device or by an Agent can't cancel it until the device side of
    Sync Nudge is wired up (Alternative O). Each follow-up is another pending
    notification against iOS's limit of 64, and more than one notification per
    planned time turns reminders into noise.
*   **Reason for Rejection**: Deferred. One reminder per planned time solves
    most of the problem, and the Planned list covers the rest whenever the user
    opens the app.

### Alternative E: Record on each Dose which planned dose it fills (D6)

*   **Pros**: Matching is exact: a Dose says "I am the 21:00 dose of
    2026-10-25". It also handles a Dose taken after midnight for the previous
    night.
*   **Cons**: Every Dose and the Agent API gain a field. The log sheet opened
    outside the Planned list, and Agent writes, wouldn't set it, so a fallback
    rule is needed anyway. Doses would then depend on the plan's identity,
    which today they deliberately don't: a Dose describes itself.
*   **Reason for Rejection**: Nearest-time matching per Compound per local date
    gives the same answer in the cases that matter, with no new field. The
    late-night case is handled by letting the user set the true date and time
    (CUJ 7).

### Alternative F: A matching window, or a day boundary later than midnight (D6)

*   **Pros**: A Dose at 00:30 would count for the 21:00 planned dose the night
    before, without the user editing anything.
*   **Cons**: It is a hidden rule. A Dose taken at 00:30 would sit on a
    different day in the Consistency view than in the Protocol Day view, which
    groups by the frozen local date.
*   **Reason for Rejection**: A record that shows the true date and time
    matches what the user sees everywhere else in the app. The log sheet gains
    a date field instead.

### Alternative G: Compare every past day against the current plan (D1)

*   **Pros**: No version history, so the data model is simpler.
*   **Cons**: Every edit rewrites how the past reads. Changing daily to Monday,
    Wednesday and Friday would turn two months of daily Doses into extras.
*   **Reason for Rejection**: It makes the Consistency view describe the past
    wrongly, which defeats its purpose.

### Alternative H: Put the period (until, cycle) on each Schedule (D4)

*   **Pros**: One Protocol can hold a cycling Compound next to ongoing ones.
*   **Cons**: A Protocol would no longer be one course, so its Effect view
    couldn't say what "during" means. A Pause would have to apply per member or
    to all of them, and both are confusing.
*   **Reason for Rejection**: The cost is one extra Protocol per distinct
    rhythm, which is how users already describe them ("my skin protocol").

### Alternative I: One Protocol per cycle phase (D4)

*   **Pros**: No cycle concept at all. Each on-period is a Protocol with a date
    range.
*   **Cons**: The user re-creates the Protocol every three months, and the
    reminders lapse whenever they forget to.
*   **Reason for Rejection**: It fails the GHK-Cu case that motivated the
    feature.

### Alternative J: Keep older clients working (dual-write) (D3)

*   **Pros**: Version-1 clients keep syncing.
*   **Cons**: Every write must also fill a legacy `frequency` that can't
    express the new rule. An older client editing a Schedule still erases its
    times, because it pushes the whole row.
*   **Reason for Rejection**: Nothing has shipped, so there are no older
    clients to protect. A hard version bump fails loudly instead of losing data
    silently.

### Alternative K: iCalendar recurrence rules (RRULE) instead of a custom rule (D4)

*   **Pros**: A standard, with libraries in both languages. It could later
    export to a calendar.
*   **Cons**: It has no on/off cycles and no untimed doses. It is far larger
    than the handful of patterns needed, so two languages would have to agree
    on, and validate, a format mostly unused here. Library behavior differs
    across implementations, which golden vectors would then have to pin.
*   **Reason for Rejection**: The custom rule is small enough to specify and
    vector-test completely.

### Alternative L: Build reminders on the rest timer's native channel (D5)

*   **Pros**: No new dependency.
*   **Cons**: Scheduling, boot handling and timezone-aware triggers would each
    be written twice, in Swift and Kotlin, and tested without Flutter's test
    tools.
*   **Reason for Rejection**: `flutter_local_notifications` already solves
    those. The timer stays on its channel, with taps routed by the `timerId`
    field. Moving the timer onto the plugin was also rejected for v1: it
    rewrites a working feature for no user benefit.

### Alternative M: Repeating OS triggers instead of a rolling horizon (D5)

*   **Pros**: One pending notification per daily time, instead of one per day,
    which uses far less of the 64-notification budget.
*   **Cons**: A repeating trigger can't skip off-cycle days, Pauses, end dates
    or already-logged planned doses. Each of those would need a second
    mechanism.
*   **Reason for Rejection**: One mechanism, the rolling scheduling horizon,
    covers every rule. The cost is a horizon of up to 14 days, which the
    Protocol screen shows.

### Alternative N: A consistency score or streak (D6)

*   **Pros**: Quick to read.
*   **Cons**: A score is a judgment, and a streak is a reward. Both push the
    user to keep taking whatever the plan holds, which breaks the
    neutral-instrument rule for substances the app must never promote.
*   **Reason for Rejection**: Statuses and counts describe what happened
    without grading it.

### Alternative O: Cancel stale reminders through Sync Nudge (D5)

*   **Pros**: The server already sends silent Sync Nudges through FCM and APNs
    (`apps/server/src/sync-nudge.ts`), including after Agent writes. The
    reconciler already runs after sync. A wired-up nudge would fix CUJ 9's
    stale reminder without new infrastructure on the server.
*   **Cons**: The device side isn't wired up: `SyncNudgeHandler.handleSilentPush`
    in `apps/mobile/lib/features/sync/services/sync_nudge_handler.dart` has no
    caller. iOS throttles silent pushes, so it would stay best-effort.
*   **Reason for Rejection**: Deferred. Wiring the device side is its own
    change, listed under Future Improvements.

### Alternative P: Convert pre-change plans instead of re-entering them (D3)

*   **Pros**: Protocols and Schedules entered before the change carry forward,
    with nothing to re-enter.
*   **Cons**: There are two ways to convert, and both cost permanent or
    duplicated code.
    *   A read-time converter keeps nullable legacy columns and a converter in
        both languages until every row is re-saved.
    *   A one-time conversion puts the rules a third time in SQL, because the
        server's migration runner runs SQL only, outside the golden vectors.
        On the device, a migration that rewrote rows would be a synced write,
        and the last device to upgrade would win.

    Old frequencies such as "twice daily" have no times, so converted plans
    would still need editing.
*   **Reason for Rejection**: Nothing has shipped, so the only rows in the old
    shape are developer data. Clearing them once costs a
    re-entry, which the test-data generator makes one command. Converting them
    costs code kept for users who don't exist.

### Alternative Q: Store an IANA timezone on each Dose instead of an offset (D2)

*   **Pros**: Keeps the zone's identity, not just its offset at that moment.
*   **Cons**: Turning it into a local time needs the timezone database in both
    languages and in the vectors.
*   **Reason for Rejection**: An offset frozen at log time is enough to rebuild
    the Dose's local time, and keeps the core timezone-free.

## Risks and Mitigations

| Risk | Impact | Mitigation | Where |
| :--- | :----- | :--------- | :---- |
| A Dose logged now from an earlier Planned list row fills a later slot | The earlier row stays "Pending", and the later slot's reminder doesn't fire | Accepted, and nearest-time matching is kept: recorded times stay true, and the Effect estimate reads them. The earlier row still shows as "Pending", and the Consistency view shows which slot each Dose filled | Open Questions, D6 |
| A reminder prompts a second dose | A duplicate TRT or GLP-1 Dose | Reduced, not removed: nearest-time matching assigns each Dose to the planned time it was nearest, and "Log all planned" never logs doses that aren't due. A dose taken but not logged is still followed by its reminder | D6, m36 vectors |
| Stale or duplicate reminders across devices | A reminder for a dose already logged elsewhere | Generic text; the Planned list is correct after sync; a per-device switch | CUJ 9, D5 |
| The scheduling horizon runs out | Reminders stop silently | The horizon date shows on the Protocol screen and the status screen | CUJ 11, D5 |
| Late delivery on Android | A reminder arrives up to about an hour late | Stated in D5 and CUJ 1; exact alarms are a follow-up | D5 |
| The notification budget is shared with the rest timer | Timer notifications fail | 48 of iOS's 64 are reserved for reminders, leaving 16 for the timer | D5 |
| Notification privacy and lock leakage | A Compound name on the lock screen | Text is always generic, `VISIBILITY_PRIVATE`, and taps go through the lock | D5 |
| Pre-change Protocol plans are cleared | Developers re-enter their plans | Nothing has shipped; Compounds and Doses are kept; the test-data generator recreates the motivating stack | D3 |
| Doses logged before the change have no frozen offset | Their local time can differ between the app (device zone) and the server (UTC) | Accepted for pre-1.0 data | D2 |
| The one-way sync cutover | Version-1 builds can't sync | Nothing has shipped; rollback is a forward fix | D3, NFRs |
| Edits to Protocol-level fields reclassify past days | Past Day Statuses change after a cycle or Pause edit | Accepted as record correction; versioning the Period is a follow-up | D1 |
| Dart and TypeScript drift apart | The app and Agents disagree | The m36 vector files, run by both in CI and registered with both ownership guards | Verification Plan |

## Non-Functional Requirements

*   **Privacy.**
    *   Notification text never names a Compound, a Protocol or an amount.
    *   Notification payloads carry only a kind and a local date.
    *   The server's observability deny-list already covers the parent keys
        that hold every new field, so no keys are added. A test (file 31)
        proves a logged Protocol or Schedule write carries none of the plan
        values. That held for the writes, except `today` (file 31). Phase
        6's reads add four keys that sit under no denied parent:
        `fromLocalDate` and `toLocalDate` at the top level of the query,
        and `plannedDays` and `dayStatuses` at the top level of the
        responses. They join the deny-list in
        `apps/server/src/observability.ts`, with a test in
        `apps/server/test/observability.test.mjs` that failed before they
        did (file 65). (Settled after Phase 6's build.)
    *   CSV export keeps excluding all Protocols data, including the new
        fields.
    *   Reminder state never leaves the device.
*   **No behavioral analytics.** Nothing records that a reminder fired, was
    shown, tapped or dismissed, locally or remotely. The reminder status screen
    reads the plugin's pending list live; it stores nothing.
*   **The logging path.** "Log all planned" and single logs write through
    `ProtocolsRepository` (`logDoses` and `logDose`) and confirm within one
    frame. No step waits on the network or on the reminder reconciler.
*   **Performance.** The Planned list computes one day for the user's Protocols
    in effect. The Consistency view computes at most 366 days for one Compound.
    The reminder reconciler computes at most 14 days. A new performance test
    (Phase 4) pins the worst case of these. On the server, the Agent's
    planned-day and Day Status reads compute at most 366 days of one user's
    Protocols. The server had no read-latency budget, so file 65 sets one
    for them: 250 ms per request. (Settled after Phase 6's build.)
*   **Rollout and rollback.** One-way. Rollback is a forward fix: a build that
    still speaks sync protocol 2 and hides the plan features. A migrated Drift
    schema can't be downgraded on the device. There is no feature flag. A new
    build sends no notifications until the user turns reminders on for a
    Protocol.

## Invariants this touches

| [Invariant](../../AGENTS.md#non-negotiable-invariants) | How it is preserved |
| :-------------------- | :------------------ |
| Derived analytics are computed, never stored or synced | Planned doses, Day Statuses and reminders are computed on read. Schedule Versions and Pauses are authored plan data, not results. |
| Sets (here, Doses) are self-describing | Doses gain a frozen UTC offset, and nothing about a Dose depends on a Schedule. Matching reads Doses but never writes to them. |
| User-facing delete is archive; no cascading deletes | Removing a Protocol Member archives it, whether the app or an Agent does it; versions are never deleted. Archiving a Protocol leaves its versions and tagged Doses untouched, and past days still count it. The one-time pre-1.0 clear (D3) is a migration of plan rows, not a user-facing delete. It leaves every Compound and Dose in place, and each Dose keeps its Protocol tag and name. |
| Restore and import are merge-only | The archive keeps format 1. An older archive imports its Compounds and Doses and skips its pre-change plan rows (D3). Nothing in this feature deletes on import. |
| Local writes never block on the network | Every write is local first. Reminders are scheduled on the device. |
| Sync is silent last-writer-wins with recoverable losers | Versions are separate rows, so concurrent Schedule edits both survive and resolve by id. Edits are Activity Log entries as today. |
| One shared two-tier validation module | D7's checks extend the existing modules in both languages, with vectors. |
| No behavioral analytics | No reminder telemetry of any kind (see Non-Functional Requirements). |

## Additional Resources

*   [AGENTS.md](../../AGENTS.md): the invariants this spec preserves, and the
    UX rules (repeat logging in two taps or fewer, gym-floor ergonomics, color
    never the only signal).
*   [CONTEXT.md](../../CONTEXT.md): Compound, Dose, Protocol, Schedule,
    Protocol Day, Effect, Template Link, Activity Log, Batch, Sync Nudge,
    Active and Archived.
*   [ARCHITECTURE.md](../../ARCHITECTURE.md): layering; the contract spine
    (the server's OpenAPI contract and the clients generated from it); sync;
    and shared two-tier validation.
*   [DESIGN.md](../../DESIGN.md): tokens and components for the Planned list,
    the editor and the Consistency view.
*   The routine "Up next" pattern this core copies:
    `apps/mobile/lib/domain/training/routine_up_next.dart`,
    `apps/server/src/agent-plan-reads.ts`,
    `packages/golden-vectors/vectors/m34-routine-up-next.json`. Vector files
    are named by the milestone that introduced them (m34, m36).

## Future Improvements

| Follow-up | Why it was deferred | Needs |
| :-------- | :------------------ | :---- |
| Log from the notification | Duplicates, writing while locked, a background write path (Alternative C) | Deterministic Dose ids per planned dose, so a repeat tap converges; a re-check of what is already logged; hidden while the lock is on; a write through `ProtocolsRepository`; evidence that opening the app is too slow |
| Cancel stale reminders through Sync Nudge | The device side isn't wired (Alternative O) | A caller for `handleSilentPush`; acceptance of iOS's throttling |
| Daily catch-up notification | Can't stay accurate across devices (Alternative D) | The Sync Nudge follow-up, or an accepted stale catch-up |
| Follow-up reminders and snooze | Notification budget and noise (Alternative D) | A per-day notification cap within the D5 budget |
| Exact Android reminders | A user-granted permission and a Play policy declaration | Opt-in `SCHEDULE_EXACT_ALARM`, falling back to inexact |
| A per-Dose "skip today" record | "Not logged" is enough for v1 | Evidence that "skipped on purpose" must look different from "Not logged" |
| Dose titration | Not needed by the motivating stack | A list of dose steps on the Schedule Rule, built on Schedule Versions |
| Version the Protocol Period | Cycle edits mid-course are rare (D1) | Evidence of mid-course cycle changes |
| A cycle-aware Effect view | Effect counts off-cycle and paused days as "during" | The core's `PlanDay` states as Effect's window input, with vectors for both languages |
| Opt-in CSV export of Protocols data | Separate from reminders | A small change of its own that keeps "excluded by default" |
| Timezone offsets for Workouts and Nutrition | The same abbreviation problem, out of this scope | The `timezoneOffsetMinutes` approach from D2, applied to those tables |

--------------------------------------------------------------------------------

## Prerequisites (separate pull requests)

These fix problems that exist independently of this feature. Each lands on its
own. P1 was folded into the related fix below.

| # | Fix | Done when | Status |
| :- | :-- | :-------- | :----- |
| P2 | Sync pull skips entity types it doesn't recognize, and sets aside malformed rows. | A pull with an unknown entity type, or a malformed known row, skips it, saves the cursor and continues. | Done ([perennia-fit/perennia#34](https://github.com/perennia-fit/perennia/pull/34), [#38](https://github.com/perennia-fit/perennia/pull/38)) |
| P3 | The Effect window agrees across languages. | `m29-effect-window.json` runs in both suites, and both pass. | Done ([perennia-fit/perennia#36](https://github.com/perennia-fit/perennia/pull/36)) |
| P4 | CI runs every golden vector in both languages. | A change to `packages/golden-vectors/**` runs both suites. | Done ([perennia-fit/perennia#37](https://github.com/perennia-fit/perennia/pull/37), [#39](https://github.com/perennia-fit/perennia/pull/39)) |
| P5 | The docs describe how Protocols data syncs. | [ARCHITECTURE.md](../../ARCHITECTURE.md) no longer says the Protocols payload is opaque to the server. | Done ([perennia-fit/perennia#44](https://github.com/perennia-fit/perennia/pull/44)) |

P5 matters because the server does read the payload, and that is what gives
the user's Agent full access.

### Related fix (not a prerequisite)

Today an Agent can write a Schedule frequency such as "daily" that makes the
app throw when it reads the Schedule. Until Phase 2 retires `frequency`, a
small independent fix closes this. The app's reader stops throwing on an
unknown frequency, and the Agent API rejects one. No golden vectors, since
Phase 2 deletes the field.

## Detailed Implementation Plan

Work lands in six phases, each its own pull request, after P5. Each phase
leaves the app buildable, the CI gate (`pnpm ci:local --changed`) green, and
the app usable. File paths start from the repository root. Line references
(`~N`) name the enclosing function, because line numbers drift.

### Data shapes (fixed by this spec)

The blocks below are notation, not literal JSON: `|` separates alternatives,
and `1..12` gives a range.

**`protocols` row** (Drift and sync payload):

| Field | Type | Meaning |
| :---- | :--- | :------ |
| `start_local_date` | `YYYY-MM-DD` | Replaces the `start_date` instant |
| `end_local_date` | `YYYY-MM-DD`, nullable | Inclusive; replaces the `end_date` instant. Null = ongoing |
| `period` | JSON, nullable | `{"v":1,"cycle":null \| {"on_days":int,"off_days":int,"anchor":"YYYY-MM-DD","anchor_is_default":bool},"pauses":[{"from":"YYYY-MM-DD","to":"YYYY-MM-DD"}]}`. Writers store null when there is no cycle and no Pause; readers accept both forms |
| `reminders_enabled` | bool, default false | Synced plan data: "remind me about this Protocol" |
| `archived_on` | `YYYY-MM-DD`, nullable | The local date of the archive, frozen when `deleted_at` is set (D1) |

**`protocol_compounds` row** (a Protocol Member) adds `archived_on`
(`YYYY-MM-DD`, nullable), frozen the same way.

**`schedules` row = one Schedule Version:**

| Field | Type | Meaning |
| :---- | :--- | :------ |
| `effective_from` | `YYYY-MM-DD` | The local date this version applies from (D1) |
| `rule` | JSON | The Schedule Rule; replaces `frequency`, which is dropped |
| `dose_amount_value`, `dose_amount_entered`, `dose_unit`, `route` | as today, now nullable | The core's `amountValue`, `amountEntered`, `unit` and `route`. All four are required for `timed` and `untimed` rules (D7 `amount_required`), and null for `as_needed` and `unscheduled` |

`rule`, version 1:

```text
{"v":1,"kind":"timed",   "days":DAYS,"times":["HH:MM", ...]}   1..12 distinct times, stored sorted (writers sort; D7)
{"v":1,"kind":"untimed", "days":DAYS,"count":int}              1..12
{"v":1,"kind":"as_needed"}
{"v":1,"kind":"unscheduled"}                                   the member has no Schedule
DAYS = {"kind":"daily"}
     | {"kind":"weekdays","weekdays":[1..7, ...]}              ISO 8601, 1 = Monday; stored sorted (writers sort; D7)
     | {"kind":"every_n_days","n":2..365,"anchor":"YYYY-MM-DD","anchor_is_default":bool}
```

An anchor is always stored. The editor sets it to the Protocol's start and
marks it as the default, until the user picks another date. A default
anchor is read as the Protocol's start, whatever date it stores (D4).

**How `rule` and `period` are stored.** In Drift each is a text column
holding the JSON. In a sync payload, an Activity Log image and a server row,
each is the same JSON text: a string holding the encoded object, never the
object itself. Every JSON-valued column in this repository travels that way
(the app's JSON columns, and the server's `nutrient_values_json`), so one
form keeps every writer and reader alike. The Agent write path encodes
through the codec and stores the text, as the app does (file 34a). Readers
on both sides also accept the decoded object, because Phase 2's Agent path
stored objects before this rule. Keeping that one branch is cheaper than a
migration of developer data. Two rows that hold the same JSON in different
forms or key orders are the same plan: the app compares decoded values,
never stored text (D1). Pauses are stored in the order written; no reader
depends on their order, including `pause_overlap`.

**`doses` row:** adds `timezone_offset_minutes` (int, nullable). A Dose payload
without the key, which every Dose logged before this change is, reads as null;
it is never treated as malformed.

**Version rules** (D1):

*   In the app, every changed save inserts a row, and an unchanged save,
    judged against the current version, inserts nothing. An Agent write
    inserts every Schedule Version it carries (D6).
*   A member's first version is dated from the Protocol's start when the
    member is created with the Protocol, or while the start is still in the
    future, and from today otherwise.
*   Later edits are dated `max(today, the latest effective_from for that
    member)`.
*   Moving the start earlier inserts re-dated copies for the members D1
    names. Moving it later inserts nothing.
*   Removing a Protocol Member archives the member row and freezes its
    `archived_on`. Versions are never edited or deleted, except that undo
    tombstones the row it inserted.

### Shared core API (pure; Dart and TypeScript mirror each other)

In Dart, `LocalDate` is the existing `ProtocolDayDate`
(`apps/mobile/lib/domain/protocols/protocols.dart`), with its date arithmetic
fixed to UTC (file 6). In TypeScript it is a `YYYY-MM-DD` string.

```text
planDays(protocols: PlanProtocol[], from: LocalDate, to: LocalDate) -> PlanDay[]
  PlanProtocol = {protocolId, startLocalDate, endLocalDate?, period?, archivedOn?,
                  remindersEnabled,
                  members: [{memberId, compoundId, archivedOn?,
                             versions: [{id, effectiveFrom, rule,
                                         amountValue?, amountEntered?, unit?, route?}]}]}
                 Rows tombstoned by undo are left out by the caller.
                 A member row covers its first effectiveFrom through archivedOn;
                 for each date the covering row of that Compound applies, the
                 larger memberId on a tie.
                 A default anchor (anchor_is_default) reads as startLocalDate (D4).
  PlanDay      = {protocolId, compoundId, localDate,
                  state: "planned" | "not_scheduled_today" | "as_needed" |
                         "no_schedule" | "removed" | "outside" | "paused" | "off_cycle",
                  planned: [{localTime: "HH:MM" | null,
                             amountValue?, amountEntered?, unit?, route?}]}

dayStatuses(planDays: PlanDay[], doses: PlanDose[], today: LocalDate) -> DayStatus[]
  PlanDose  = {doseId, compoundId, localDate, localTime: "HH:MM", sequence: int}
  DayStatus = {compoundId, localDate,
               status: "not_planned" | "paused" | "off_cycle" | "pending" |
                       "logged" | "partly_logged" | "not_logged",
               notPlannedReason?: "not_scheduled_today" | "as_needed" |
                                  "no_schedule" | "removed" | "outside",
               plannedCount, loggedCount, extraCount,
               fills: [{slot: int, protocolId, plannedLocalTime: "HH:MM" | null,
                        amountValue?, amountEntered?, unit?, route?,
                        doseId: string | null}]}
  Dates after `today` are not returned. A Dose whose Compound and date has no
  PlanDay is ignored. Matching and status order: D6.

dueUnfilled(dayStatuses: DayStatus[], today: LocalDate, nowLocalTime: "HH:MM")
  -> [{compoundId, slot, protocolId, amountValue, amountEntered, unit, route}]
  Only `today`'s unfilled slots, timed at or before now, or untimed.

effectBoundsFromLocalDates({startLocalDate, endLocalDate, timezoneOffsetMinutes})
  -> EffectBounds{startDate: instant, endDate: instant | null}      (D2)
endDateForDoseCount({startLocalDate, rule, doseCount, period?}) -> LocalDate | null
  (Dart only; D6; null is "unavailable"; a default anchor reads as startLocalDate)

compareScheduleVersions(a, b) -> int
  D1's version order: effectiveFrom, then id.
applyingScheduleVersion(sorted, localDate) -> version | null
  The version that applies on localDate: the last of `sorted` (already in
  that order) dated on or before it. Null when none applies yet.
```

**Shared version order.** `compareScheduleVersions` and
`applyingScheduleVersion` are exported from the core in both languages
(`protocol_plan.dart`, `protocol-plan.ts`). `applyingScheduleVersion` is
generic over the entry type. In Dart it takes the date reader as a named
`effectiveFrom` function, and `compareScheduleVersions` takes two
`ScheduleVersion`s. In TypeScript both take any object with an
`effectiveFrom` (and, to compare, an `id`). `planDays`, the app's repository and
the Agent write and read paths all use them, so "which version applies" and
"the current version" (the last in this order) are decided in one place per
language.

Archive dates arrive already frozen (`archived_on`). No function parses an
instant or a timezone, except `effectBoundsFromLocalDates`, which applies the
offset it is given. It uses the same local-midnight-minus-offset conversion as
the local-time anchors in `apps/server/src/metric-reading-normalization.ts`.

**Parameters.** `planDays`, `dayStatuses` and `dueUnfilled` take positional
parameters in both languages. In Dart, `effectBoundsFromLocalDates` and
`endDateForDoseCount` take named parameters, and `EffectBounds` is a class in
`apps/mobile/lib/domain/effect/effect.dart`. There, `endLocalDate` is
required but may be null (an ongoing Protocol), so no caller can leave it
out by mistake. In TypeScript,
`effectBoundsFromLocalDates(startLocalDate, endLocalDate, timezoneOffsetMinutes)`
takes the same three positionally and returns `{startDate: Date, endDate:
Date | null}`. It throws a `RangeError` for a fractional offset, as Dart's
`int` type rules out, and from Phase 2 for one outside −720 to +840 (D2).

**Coverage.** `planDays` returns one PlanDay for every date in `[from, to]`,
inclusive, for each Protocol and each Compound that has at least one member
row in that Protocol, whatever the row's archive date or versions. That
includes dates outside the Protocol's bounds, which come back with state
`outside` and an empty `planned` list. So one Compound in one Protocol over a 30-day range is
always 30 PlanDays. `planned` is non-empty exactly when `state` is `planned`.
`notPlannedReason` is present exactly when `status` is `not_planned`.

**Output order,** in both languages, so two outputs compare equal as lists:

| Output | Ordered by |
| :----- | :--------- |
| `planDays` | `localDate`, then `protocolId`, then `compoundId` |
| `PlanDay.planned` | the rule's stored order: its `times`, or `count` untimed entries |
| `dayStatuses` | `localDate`, then `compoundId` |
| `DayStatus.fills` | `slot` |
| `dueUnfilled` | `compoundId`, then `slot` |

Ids, dates and times compare by UTF-16 code unit, Dart's `String.compareTo`,
so both languages sort them the same way.

**Codecs.** The rule and period decoders reject, besides any `v` other than
1 and any unknown `kind`:

*   a value of the wrong JSON type: a string where an object, array, integer
    or boolean belongs;
*   a fractional number where an integer belongs. A whole number written as a
    float (`2.0`) reads as that integer;
*   a date that isn't a real `YYYY-MM-DD` date (`2026-02-30`, `2026-13-01`, or
    another format). Every four-digit year reads as written, including years
    0 to 99;
*   a time that isn't `HH:MM` from 00:00 to 23:59, such as `9:00` or `24:00`.

In Dart, the decoders of the amount-carrying shapes (Schedule Version,
planned dose and fill) also reject a `unit` or `route` that isn't in the Dose
registries (`DoseUnit`, `DoseRoute`). TypeScript carries both as strings, and
the server's write path judges them through `amount_required` (D7).

The decoders also enforce safe ceilings, the same in both languages and
pinned by codec vectors. They read their bounds from the limits (D7):

| Value | Codec accepts | Validator accepts (D7) |
| :---- | :------------ | :--------------------- |
| every-N `n` | 1 to 365 | 2 to 365 (`every_n_range`) |
| untimed `count` | 1 to 12 | 1 to 12 (`untimed_count`) |
| timed `times` | 1 to 12 times | 1 to 12 (`times_count`) |
| cycle `on_days`, `off_days` | each 0 to 3650, summing to at least 1 | each 1 to 3650 (`cycle_lengths`) |

The ceilings keep a synced row that was never validated from planning a
billion doses, or a day count past what both languages hold exactly. The
codecs check nothing else about ranges: an every-N of 1, or a cycle with no
off-period, decodes, and rejecting it is D7's job. Dart throws a
`FormatException`; TypeScript throws `ProtocolPlanCodecError`. In Dart the
rule and cycle constructors enforce the same bounds, throwing an
`ArgumentError`, so no value outside them can be built.

**A plan period under one day.** An every-N rule with N < 1, or a cycle whose
on and off days sum to less than 1, can't come from validated data, and the
core never plans one. In TypeScript, `planDays` decodes every rule and
period, so it throws `ProtocolPlanCodecError` on one. In Dart such a value
can't be built: the every-N constructor throws a `RangeError`, and a
zero-length cycle an `ArgumentError`, so `planDays` and
`endDateForDoseCount` never meet one.

**Vector case shapes.**

*   **Both files** carry `name`, `domain`, `schemaVersion`, `schema` and
    `cases`. Any case may carry an optional `note`: why the case exists and
    which rule it pins. Runners ignore it.
*   **File 1:** each case has `name`, `function` (`rule_codec`,
    `period_codec`, `plan_days`, `day_statuses`, `due_unfilled` or
    `effect_bounds`), `input` (that function's arguments, by parameter name)
    and `expected` (its return value). A codec case holds the JSON in
    `input.json` and the decoded value, or `{"rejects": true}`, in
    `expected`.
*   **File 2:** each case has `name`, `validator` (`schedule_rule` or
    `protocol_period`), `input` (the validator's parameters) and
    `expected.{accepted, errorRules, warningRules}`, as the plan-validation
    vectors do. The file also carries a top-level `limits` block.

### Target Files to Create/Modify

#### Phase 1: the shared core and its vectors (no user-visible change)

Each vector file carries one top-level `domain`, and is registered with both
ownership guards (files 11 and 16). Each Dart runner must contain the literal
`golden-vectors`, because CI finds runners with
`git grep -l golden-vectors -- 'test/*_test.dart'`. That only sees tracked
files, so stage a new runner before running the gate locally.

##### 1. `packages/golden-vectors/vectors/m36-protocol-plan.json` (Create)

*   **Type / Scope**: Golden vectors, `domain: "protocol-plan"`, `schemaVersion: 1`.
*   **Proposed Changes**: Cases in the file-1 shape. **Required cases:**
    *   CUJs 1-7, with their dates;
    *   **matching:** the 20:50-fills-21:00 case; an early and a late Dose; two
        morning Doses; mixed timed and untimed slots; an extra Dose;
    *   **plan structure:**
        *   an every-N-days anchor before the range;
        *   a cycle anchor before the start;
        *   a backdated Protocol start;
        *   moving the start later past an edit;
        *   moving the start earlier;
        *   a default anchor moving with the start;
        *   overlapping Protocols for one Compound;
    *   **versions and members:**
        *   two versions on the same date (the id tie-break);
        *   a Compound added mid-course;
        *   a removed and re-added member;
        *   a member removed and re-added the same day (the larger `memberId`
            wins);
        *   a member removed today (still planned today);
        *   a member with no versions, and one with an `unscheduled` version;
        *   an archived Protocol's past days, including the archive date;
    *   **statuses:** each `notPlannedReason`;
    *   **`due_unfilled`:** a later-timed row excluded, untimed included, and
        past dates excluded;
    *   **`effect_bounds`:** offsets −180, 0 and +540, and an open end.

##### 2. `packages/golden-vectors/vectors/m36-protocol-plan-validation.json` (Create)

*   **Type / Scope**: Golden vectors, `domain: "protocol-plan-validation"`,
    `schemaVersion: 1`.
*   **Proposed Changes**: Every D7 check, passing and failing, in the file-2
    shape, with a `limits` block of `{maxTimesPerDay: 12, maxUntimedCount: 12,
    minEveryNDays: 2, maxEveryNDays: 365, maxCycleLengthDays: 3650,
    warnTimesPerDay: 6}`.
    *   `amount_required`'s two less obvious failures each have a case: a
        blank `amountEntered` (`timed-rule-with-blank-amountEntered-rejects`)
        and a Dose-validator hard error on a present amount
        (`timed-rule-with-negative-amount-rejects`), both →
        `[amount_required]`. Both runners check the file's `schemaVersion`.

##### 3. `packages/golden-vectors/vectors/m36-protocol-plan.schema.json` and `packages/golden-vectors/vectors/m36-protocol-plan-validation.schema.json` (Create)

*   **Type / Scope**: JSON Schema.
*   **Proposed Changes**: One schema each for files 1 and 2, as
    `packages/golden-vectors/vectors/m34-routine-up-next.schema.json` does for
    its file. Each `schemaVersion` constant matches its runners' constants.

##### 4. `packages/golden-vectors/vectors/README.md` (Modify)

*   **Proposed Changes**: A section for m36 stating the version rule (a file's
    constant and its runners' constants move together), and that cases contain
    no IANA zones: a UTC offset appears only as an input of `effect_bounds`
    cases.

##### 5. `apps/mobile/lib/domain/protocols/protocol_plan.dart` (Create)

*   **Type / Scope**: Dart pure domain.
*   **Proposed Changes**:
    *   Types and JSON codecs for Schedule Rule, Protocol Period, Pause,
        Schedule Version, `PlanProtocol`, `PlanDay`, `PlanDose` and
        `DayStatus`.
    *   The codecs reject unknown `kind`s and any `v` other than 1, and are
        as strict as [Shared core API](#shared-core-api-pure-dart-and-typescript-mirror-each-other)
        **Codecs** says, throwing a `FormatException`.
    *   Uses `ProtocolDayDate` for dates.
    *   Also public, as built:
        *   `ProtocolPlanValidationLimits` (D7), which file 8 re-exports;
        *   `protocolPlanJsonVersion`, the one JSON `v` (1);
        *   the `HH:MM` helpers `isPlanLocalTime`, `planLocalTime` and
            `planLocalTimeMinutes`;
        *   `planWholeNumber`, the whole-number reading the decoders and
            validators share;
        *   the types `PlanAmount` (the four amount fields), `PlanMember`,
            `PlannedDose` and `PlanSlotFill` (one entry of a `DayStatus`'s
            `fills`).

##### 6. `apps/mobile/lib/domain/protocols/protocols.dart` (Modify, Phase 1 part)

*   **Proposed Changes**: `ProtocolDayDate.addDays` (~73-78) computes through
    `DateTime.utc` instead of a local `DateTime`, so a daylight-saving change
    can't repeat or skip a date. New `daysBetween(other)` and `isoWeekday`
    use the same UTC arithmetic.

##### 7. `apps/mobile/lib/domain/protocols/protocol_plan_days.dart` (Create)

*   **Proposed Changes**: `planDays`, `dayStatuses`, `dueUnfilled` and
    `endDateForDoseCount`, following D1, D4 and D6, with the coverage and
    output order in the Shared core API. `endDateForDoseCount` takes named
    parameters and returns null for "unavailable" (D6). It does no I/O.
    Also public, as built: `DueUnfilledDose`, the row `dueUnfilled`
    returns, and `minDoseCountForEndDate` and `maxDoseCountForEndDate` (1
    and 1000), which the editor's "N doses" helper reads.

##### 8. `apps/mobile/lib/domain/protocols/protocol_plan_validation.dart` (Create)

*   **Proposed Changes**:
    *   `validateScheduleRule` and `validateProtocolPeriod`, with the D7
        signatures and check assignment.
    *   Both return `DoseValidationResult`.
    *   It re-exports `ProtocolPlanValidationLimits`, the limits in file 2,
        from file 5. File 5 defines the class, so its types can enforce the
        codec ceilings without an import cycle.
    *   It follows the layout of
        `apps/mobile/lib/domain/training/plan_validation.dart`.

##### 9. `apps/mobile/lib/domain/effect/effect.dart` (Modify)

*   **Proposed Changes**: Adds `effectBoundsFromLocalDates`, with named
    parameters, and the `EffectBounds{startDate, endDate}` class it returns
    (D2). The Effect math is unchanged.

##### 10. Dart tests (Create)

*   `apps/mobile/test/domain/protocol_plan_golden_test.dart`: every file-1
    case against files 5, 7 and 9, and its schema-version constant.
*   `apps/mobile/test/domain/protocol_plan_validation_test.dart`: every
    file-2 case against file 8; the `limits` block equals
    `ProtocolPlanValidationLimits`; and its schema-version constant.
*   `apps/mobile/test/domain/protocol_plan_dose_count_test.dart`:
    `endDateForDoseCount` for CUJ 4, a two-time rule, cycles, Pauses,
    `as_needed`, and a `doseCount` outside 1-1000.
*   `apps/mobile/test/domain/protocol_day_date_dst_test.dart`: `addDays`,
    `daysBetween` and day iteration across both daylight-saving changes,
    with the process timezone set to `America/Sao_Paulo` and
    `Europe/Lisbon` through the `TZ` environment variable, under
    `flutter test`. A process can't change its own zone, so the test runs
    its assertions in its own process, then runs them again once per zone
    in a child process with `TZ` set. As built, the assertions live in
    `apps/mobile/test/domain/protocol_day_date_dst_checks.dart`, which the
    test imports and also runs in each child as a plain Dart VM, not a child
    `flutter test`. Each child first asserts that its zone took effect, so a
    platform that ignores `TZ` fails rather than passing without testing
    anything.

##### 11. `apps/mobile/test/domain/golden_vector_ownership_test.dart` (Modify)

*   **Proposed Changes**: Map `protocol-plan` to
    `test/domain/protocol_plan_golden_test.dart`, and
    `protocol-plan-validation` to `test/domain/protocol_plan_validation_test.dart`.

##### 12. `apps/server/src/protocol-plan.ts` (Create)

*   **Type / Scope**: TypeScript twin of files 5 and 7, except
    `endDateForDoseCount`.
*   **Proposed Changes**: The same functions and JSON, with no database access.
    Dates are `YYYY-MM-DD` strings with UTC epoch-day arithmetic. The codecs
    throw `ProtocolPlanCodecError`, and dates are checked without `Date.UTC`,
    which would read years 0-99 as 1900-1999.
    *   Also public, as built:
        *   `PROTOCOL_PLAN_VALIDATION_LIMITS` (D7), which file 13 re-exports;
        *   `encodeScheduleRule` and `encodeProtocolPeriod`, which write a
            decoded value back as its normalized stored JSON;
        *   `MS_PER_DAY`, `epochDay` and `isValidLocalDate`, for local-date
            arithmetic;
        *   `isJsonObject` and `isWholeNumber`, for reading stored JSON;
        *   `compareIds`, the UTF-16 code-unit order of the Shared core API,
            and `pushToGroup`, which appends to a keyed group.

##### 13. `apps/server/src/agent-validation.ts` (Modify)

*   **Proposed Changes**: Adds `validateAgentScheduleRule` and
    `validateAgentProtocolPeriod` next to `validateAgentDose`, with the D7
    signatures and the same issue shape, and re-exports
    `PROTOCOL_PLAN_VALIDATION_LIMITS` from file 12. File 12 defines the
    constant, because this module imports that one. Both
    take the stored JSON, and the period validator takes `YYYY-MM-DD` bounds
    that must be real dates (D7).

##### 14. `apps/server/src/agent-protocols.ts` (Modify, Phase 1 part)

*   **Proposed Changes**: Adds `effectBoundsFromLocalDates` next to
    `deriveEffectWindow`, with positional parameters, throwing a `RangeError`
    for a fractional offset. Nothing calls it yet.

##### 15. `apps/server/src/index.ts` (Modify, Phase 1 part)

*   **Proposed Changes**: Re-exports file 13's validators and limits, and file
    12's functions, alongside the existing validation exports, because the
    golden runners import from `src/index.ts`.

##### 16. TypeScript tests (Create/Modify)

*   `apps/server/test/protocol-plan.golden.test.mjs` (Create): runs every
    file-1 case against files 12 and 14.
*   `apps/server/test/agent-validation.golden.test.mjs` (Modify):
    *   adds `protocol-plan-validation` to `VALIDATORS_BY_DOMAIN`, dispatching
        on the case's `validator` like `validatePlanVectorCase`;
    *   asserts the `limits` block equals `PROTOCOL_PLAN_VALIDATION_LIMITS`;
    *   adds `protocol-plan` to `DOMAINS_OWNED_ELSEWHERE`, owned by the new
        runner.

##### 17. `apps/server/package.json`, `.github/workflows/ci.yml` and `tools/ci-local.mjs` (Modify)

*   **Proposed Changes**:
    *   Add `test/protocol-plan.golden.test.mjs` to the `test:golden-vectors`
        script.
    *   Add `apps/server/src/protocol-plan.ts` and
        `apps/server/test/protocol-plan.golden.test.mjs` to the
        `golden_vectors` path filters, in `ci.yml` and `ci-local.mjs` in the
        same commit.

#### Phase 2: storage, sync, the plan editor, Effect input and the Agent plan shape

##### 17a. The plan core, its validators and vectors: rules settled after Phase 1 (Modify)

This entry is lettered so the numbers of every later file stay as they were.

*   **Files**: `apps/mobile/lib/domain/protocols/protocol_plan_validation.dart`,
    `apps/server/src/agent-validation.ts`,
    `apps/mobile/lib/domain/effect/effect.dart`,
    `apps/server/src/agent-protocols.ts` (`effectBoundsFromLocalDates` only),
    the two m36 vector files and both their schemas, the two runners
    that read `effect_bounds` cases (`apps/mobile/test/domain/protocol_plan_golden_test.dart`,
    `apps/server/test/protocol-plan.golden.test.mjs`), and these, which the
    changes below also need:
    *   `apps/mobile/lib/domain/protocols/protocol_plan.dart` and
        `apps/server/src/protocol-plan.ts`: export `compareScheduleVersions`
        and `applyingScheduleVersion` ([Shared core API](#shared-core-api-pure-dart-and-typescript-mirror-each-other));
    *   `apps/mobile/test/domain/protocol_plan_validation_test.dart`: assert
        `maxPauses` in the `limits` block;
    *   `packages/golden-vectors/vectors/m36-protocol-plan.schema.json`:
        `effect_bounds` cases may expect `{"rejects": true}`, and their
        `timezoneOffsetMinutes` input is unbounded, so a case can carry an
        offset outside the range. The cycle's `on_days` and `off_days`
        minimum is 0, not 1, so a codec case can expect a cycle the codecs
        read and D7's `cycle_lengths` rejects. As built, that is the only
        bound relaxed: the schema still holds every-N `n` to 2 or more,
        `times` to distinct values and weekdays to distinct values from 1
        to 7. So no case can expect the codec to read `n = 1`, which it
        does ([Shared core API](#shared-core-api-pure-dart-and-typescript-mirror-each-other)).
*   **Proposed Changes**:
    *   **`amount_absent`** (D7) in both validators, after `amount_required`:
        an `as_needed` or `unscheduled` rule with any of `amountValue`,
        `amountEntered`, `unit` or `route` non-null rejects.
    *   **`pause_count`** (D7) in both validators, after `bounds_order`: more
        than `maxPauses` Pauses rejects, and the other Pause checks don't
        run. `maxPauses: 100` joins `ProtocolPlanValidationLimits`,
        `PROTOCOL_PLAN_VALIDATION_LIMITS`, the vector's `limits` block and
        that block's schema (`required` and `properties`). `schemaVersion`
        stays 1: the case shape is unchanged, and every runner changes in
        the same pull request.
    *   **The offset range** (D2) in both `effectBoundsFromLocalDates`: an
        offset outside −720 to +840 throws a `RangeError`. An
        `effect_bounds` case may now expect `{"rejects": true}`, as a codec
        case does, and both runners map a `RangeError` to it.
*   **Vectors to add** (each with a `note`):
    *   in `m36-protocol-plan-validation.json`:
        *   `as-needed-rule-with-an-amount-rejects` → `[amount_absent]`;
        *   `unscheduled-rule-with-a-unit-rejects` → `[amount_absent]`;
        *   `one-hundred-pauses-are-valid` → accepted;
        *   `one-hundred-and-one-overlapping-pauses-report-only-pause-count`
            → `[pause_count]`;
        *   `three-bad-times-report-times-format-once` → `[times_format]`;
        *   `several-overlapping-pauses-report-pause-overlap-once` →
            `[pause_overlap]`;
        *   `schedule-rule-errors-come-in-table-order`: an every-N timed rule
            with times `["9:00", "9:00"]`, `n` 1, an impossible anchor and no
            unit → `[times_format, times_distinct, every_n_range,
            anchor_date, amount_required]`;
        *   `thirteen-times-rejects-and-warns` (exists) pins warnings judged
            alongside errors;
        *   `protocol-period-errors-come-in-table-order`: an impossible cycle
            anchor, 0 on-days, an end before the start, a reversed Pause, a
            Pause outside the bounds and two overlapping Pauses →
            `[anchor_date, cycle_lengths, bounds_order, pause_order,
            pause_bounds, pause_overlap]`;
        *   `unsorted-times-and-weekdays-are-valid` → accepted;
    *   in `m36-protocol-plan.json`:
        *   `every-n-days-anchor-after-the-start-plans-backwards`: every 3 days
            anchored 2026-10-05, start 2026-10-01; 2026-10-02 and 2026-10-05
            planned, the other days `not_scheduled_today`;
        *   `cycle-anchor-after-the-start-counts-backwards`: 3 on and 2 off
            anchored 2026-10-05, start 2026-10-01; 2026-10-01 to 2026-10-02
            planned, 2026-10-03 to 2026-10-04 `off_cycle`, 2026-10-05
            planned;
        *   `day-statuses-ignore-a-dose-with-no-plan-day`: a Dose of a
            Compound with no PlanDay yields no Day Status, and no other
            Compound's `extraCount` changes;
        *   `rule-codec-keeps-unsorted-times-in-stored-order`: the codec
            reads `["21:00", "09:00"]` and encodes it unchanged;
        *   `effect-bounds-offset-minus-720` and
            `effect-bounds-offset-plus-840`: the two ends of the range;
        *   `effect-bounds-rejects-offset-minus-721` and
            `effect-bounds-rejects-offset-plus-841` → `{"rejects": true}`;
        *   no case for a fractional offset: Dart's `int` can't express one,
            so it stays a TypeScript guard.

##### 18. `apps/mobile/lib/data/local/app_database.dart` (Modify)

*   **Type / Scope**: Drift schema, the current version + 1 (60 → 61 as of
    this revision).
*   **Proposed Changes**: In the `from < 61` step, following the v55
    precedent:
    1.  Delete `activity_log` rows whose `entity_table` is `protocols`,
        `protocol_compounds`, `schedules` or `protocol_target_outcomes`.
        Delete `deferred_sync_changes` and `quarantined_sync_changes` rows for
        the same tables. This keeps old images from being pushed or applied
        later (D3).
    2.  Delete every row of `protocol_target_outcomes`, `schedules`,
        `protocol_compounds` and `protocols`, in that order.
    3.  `deleteTable` and `createTable` for `protocols` and `schedules` in
        the new shapes. `start_date`, `end_date` and `frequency` are gone.
    4.  `createIndex` for a new index `schedules_protocol_compound_effective_from_index`
        on `(protocol_compound_id, effective_from)`. `createTable` doesn't
        install `@TableIndex`. The old `schedules_protocol_compound_id_index`
        is dropped with the old table and not recreated: the new index leads
        with `protocol_compound_id`, so it serves every lookup by member,
        and a second index would only slow writes.
    5.  `addColumn` for `doses.timezone_offset_minutes` and
        `protocol_compounds.archived_on`. Each is guarded with
        `_columnExists`, because upgrades from below 37, 41 or 42 already
        create those tables in the current shape.

    Mark nothing as pending sync. After the step, `PRAGMA foreign_key_check`
    must return no rows.

##### 19. `apps/mobile/lib/data/local/app_database.g.dart` (Regenerate)

*   **Proposed Changes**: `build_runner` output for file 18.

##### 20. `apps/mobile/lib/domain/protocols/protocols.dart` and `apps/mobile/lib/domain/protocols/protocol_validation.dart` (Modify, Phase 2 part)

*   **Proposed Changes**:
    *   `ScheduleFrequency`, `scheduleFrequencyLabel` and
        `scheduleFrequencyFromName` are removed.
    *   `ScheduleDraft` and `ScheduleRecord` replace `frequency` with `rule`,
        and make the amount, unit and route nullable. `ScheduleRecord` gains
        `effectiveFrom`.
    *   `ProtocolDraft`, `ProtocolSummaryRecord` and `ProtocolRecord` replace
        their `DateTime` bounds with `startLocalDate` and `endLocalDate`, and
        gain `period` and `remindersEnabled`.
    *   A Protocol read exposes, for each member, `currentVersion` (the
        latest `effectiveFrom`, then the larger id), which the editor shows
        and an unchanged save is compared with (D1), and
        `versionInEffectToday`, for surfaces that describe today.
    *   `DoseRecord` gains `timezoneOffsetMinutes` and a derived `localTime`.
    *   `validateProtocolWindow` is removed from `protocol_validation.dart`;
        its callers use D7's `bounds_order` check.
    *   Doc comments that cite unpublished section numbers (they read
        `PROTOCOLS.md §`) are rewritten to state the rule they rely on.

##### 21. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

*   **Type / Scope**: `ProtocolsRepository` and `EffectRepository`.
*   **Proposed Changes**:
    *   **Logging:**
        *   `_logDose` writes `draft.tookAt.toLocal().timeZoneOffset.inMinutes`,
            since `tookAt` is converted to UTC there.
        *   New `logDoses(List<DoseSnapshotDraft>)` runs one transaction and
            one Batch over `_logDose`.
        *   `_editDose` re-freezes `localDate`, `timezone` and
            `timezoneOffsetMinutes` when the time changes, and keeps a null
            offset null otherwise.
    *   **Schedules:**
        *   `_reconcileSchedule` compares the draft with the member's
            current version, decoded, and inserts a version row only when it
            differs, dated by D1. It no longer updates in place.
        *   A null draft inserts an `unscheduled` version, unless the member
            has no versions yet, in which case it inserts nothing.
        *   Every inserted version has its `times` and `weekdays` sorted,
            and null amount fields for an `as_needed` or `unscheduled` rule
            (D7).
        *   `_activeScheduleQuery(...).getSingleOrNull()` and every read that
            assumes one Schedule per member (`listProtocols`,
            `_protocolsFromRows`) select by version instead. A member has many
            rows.
        *   A start-date change inserts the re-dated copies D1 describes,
            before the save's member and Schedule changes. As built in
            Phase 2 it also copies on a later move, and copies only members
            the save keeps; file 34a brings it to D1.
    *   **Archives:**
        *   `_replaceProtocolMembers` no longer calls
            `_reconcileSchedule(row.id, null, …)` on removal.
        *   Archiving a Protocol Member or a Protocol sets `deleted_at` and
            freezes `archived_on` as the device's local date at that moment.
    *   **Protocols:** create and edit write local-date bounds, `period` and
        `reminders_enabled`, validated by file 8. Editing or archiving an
        archived Protocol throws a `StateError`.
    *   **`today`.** `createProtocol`, `editProtocol` and `archiveProtocol`
        take an optional named `today` (`ProtocolDayDate`), defaulting to
        the device's local date at the write's timestamp. It dates versions
        and `archived_on`, and lets tests pin "today" without a fake clock.
        No caller in the app passes it.
    *   **Rejects** from file 8 throw `DoseValidationException` (D7), before
        anything persists.
    *   **Effect:** `EffectRepository.windowForProtocol` (~7577) passes
        `effectBoundsFromLocalDates(…, device offset)` into
        `effectWindowForProtocol`.
    *   **Sync images:**
        *   `_doseImage` and `_doseCompanionFromImage` carry
            `timezone_offset_minutes`, and a missing key reads as null.
        *   The protocol, member and schedule images carry the new fields,
            with `rule` and `period` as JSON text (Data shapes). An image is
            malformed, and the existing quarantine sets it aside, when it is
            missing a required plan field (a protocol's `start_local_date`
            or `reminders_enabled`, a schedule's `effective_from` or `rule`),
            when a date isn't a real `YYYY-MM-DD`, or when the rule or period
            codec rejects its JSON. A missing nullable field
            (`end_local_date`, `period`, `archived_on`, the amount fields)
            reads as null. Every pre-change protocol or schedule image lacks
            a required field, so it is quarantined.

##### 22. `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart` and `apps/mobile/lib/l10n/app_en.arb` (Modify, Phase 2 part)

*   **Proposed Changes**:
    *   **Bounds:** date-only pickers bound to the local dates. The start-date
        formatting in the Protocol list tile (~210) reads `startLocalDate`.
    *   **A "Period" section:**
        *   an "Until" switch with an end date;
        *   an "N doses" helper that asks which Protocol Member to count and
            fills the end date from `endDateForDoseCount`;
        *   a "Cycle" switch with on days, off days and an anchor date that
            defaults to the start;
        *   a Pauses list with add, edit and remove.
    *   **Each Protocol Member's Schedule editor** shows `currentVersion`,
        and replaces the frequency picker with:
        *   days: daily, weekday chips, or every N days;
        *   times: a list of time pickers, or an untimed count;
        *   or "As needed", or "No schedule", either of which clears the
            amount, unit and route (D7 `amount_absent`).
    *   **Defaults for new values,** so a new rule is valid as soon as it
        is picked, and one choice gets a working plan:
        *   a new member starts with no Schedule, and its amount fields take
            its Compound's default unit and route;
        *   a new timed rule is daily at 09:00; a new untimed rule is daily
            with a count of 1;
        *   switching to every N days starts at N = 2 with a default anchor
            (the start); switching to weekdays preselects the start's
            weekday;
        *   "Add a time" suggests one hour after the last time;
        *   a new cycle starts with empty on and off counts, which the user
            must fill (D7 `cycle_lengths` rejects until then), and a default
            anchor.
    *   **Saving:** "No schedule" saves a null draft, which file 21 turns
        into an `unscheduled` version, or into nothing for a member with no
        versions. Ending early is setting the "Until" end date to today;
        there is no separate "End early" action.
    *   **The "N doses" helper** reads "Unavailable" when the member's rule
        is invalid, `as_needed` or `unscheduled`, while the cycle or Pauses
        fail validation, or when `endDateForDoseCount` returns null.
    *   **Validation:** rejects and warnings from file 8 show inline, as Dose
        validation does. Hard rejects appear after the first save attempt,
        then update live as the user edits. Warnings show live and never
        block a save. Inline issues use DESIGN.md's text colors with an
        icon, not the error red, because an issue under a field is guidance
        rather than a failure, and color is never its only signal.
    *   **Text buttons** use `textPrimary`. DESIGN.md's cyan primary fails
        WCAG AA contrast for text on the light theme.
    *   **Strings:** only the editor's own strings go into `app_en.arb`, and
        the generated `app_localizations*.dart` is regenerated. Strings the
        rest of the Protocol screen already hard-codes stay as they are; the
        move is not this feature's.

##### 23. `apps/mobile/lib/features/protocols/widgets/effect_screen.dart` (Modify)

*   **Proposed Changes**: For a Protocol with a cycle or Pauses, shows
    "Off-cycle and paused days are counted as during." under the existing
    `EffectScreen.disclaimerText`. Its string goes into `app_en.arb`. The
    screen reads the Protocol's period from `protocolDetailProvider`, which
    the Protocol screen already watches, rather than adding a period field
    to Effect's own state, which is about outcomes, not the plan.

##### 24. `apps/mobile/lib/features/sync/repositories/sync_repository.dart` (Modify)

*   **Proposed Changes**: `syncProtocolVersion` 1 → 2.

##### 25. `apps/mobile/lib/data/repositories/portable_archive_repository.dart` (Modify)

*   **Proposed Changes**: `archiveFormatVersion` stays 1, and the manifest's
    `schemaVersion` tells old shapes apart. For `schemaVersion < 61`:
    *   skip decoding `protocols`, `protocol_compounds`, `schedules` and
        `protocol_target_outcomes`, before `_decodeRows` and the row-count
        checks, alongside `_mayBeAbsentFromArchive`;
    *   drop those tables' `activity_log` rows;
    *   import Compounds and Doses as today.

    Merge-only behavior is unchanged.

##### 26. `apps/mobile/tool/test_data/test_data_generator.dart` and `apps/mobile/test/tool/test_data_generator_test.dart` (Modify)

*   **Proposed Changes**: A new `includeProtocols` option, default true,
    following `includeBodyWeight` and `includeNutrition`.
    *   **Compounds:** TRT, AgeMate, MNEM, GHK-Cu and BPC-157 are created.
        Creatine is one of the app's seeded Compounds, so the stack reuses
        the seeded row (its stable id) rather than adding a second
        "Creatine".
    *   **Protocols,** written through the app's repositories:
        *   "Daily", starting at the range start: TRT, AgeMate and MNEM at
            09:00, creatine at 17:00;
        *   "Skin": GHK-Cu at 21:00 on a 60/30 cycle, starting on its anchor
            60 days before the range end, with the anchor left at its
            default;
        *   "Shoulder": BPC-157 at 21:00, starting 10 days before the range
            end, for 20 doses.
    *   **Doses:** over the generator's whole `weeks` and `endDate` range
        (12 weeks by default), one per planned dose, with one day in six
        left unlogged. Each is timed within 15 minutes either side of its
        planned time, as people take them, and a Dose whose time is still
        ahead of now is not written. Amounts are placeholders for exercising
        the app, not dosing guidance, and the code says so.
    *   **Summary:** counts in `TestDataSummary`.

    The test asserts the Compounds, Protocols and Dose counts.

##### 27. `apps/server/src/sync.ts` (Modify)

*   **Proposed Changes**: `SYNC_PROTOCOL_VERSION` 1 → 2.

##### 28. `apps/server/drizzle/<next>_clear_protocol_plans.sql` (Create)

*   **Type / Scope**: A custom migration, created with
    `pnpm --filter @perennia/server db:generate --custom --name=clear_protocol_plans`,
    which also writes its journal entry. It is 0033 as of this revision.
*   **Proposed Changes**: Deletes every row of `protocol_target_outcomes`,
    `schedules`, `protocol_compounds` and `protocols`, in that order (D3).

##### 29. `apps/server/src/agent-protocols.ts` (Modify, Phase 2 part)

*   **Proposed Changes**:
    *   **Schemas.** `AgentProtocolBatchWriteRequestSchema` and its Protocol,
        member and Schedule sub-schemas become `.strict()`, so `frequency`
        and `deletedAt` are rejected rather than stripped. The target-outcome
        sub-schema stays as it was: not strict, with its `deletedAt`, which
        is how an Agent archives an outcome (the skill's API reference says
        so).
        *   The request gains a required top-level `today`, which must be
            within one day of the server's UTC date. Only this write gains
            it (D6).
        *   Entities gain `archived: boolean`, default false.
        *   The Protocol gains `startLocalDate`, `endLocalDate`, `period` and
            `remindersEnabled`. `endLocalDate` and `period` default to null
            and `remindersEnabled` to false, and the schema's description
            says the write replaces the whole row (D6).
        *   The Schedule takes `rule` and the amount fields, and has no
            `effectiveFrom`.
        *   `today`, `startLocalDate` and `endLocalDate` must be real
            `YYYY-MM-DD` dates (`isValidLocalDate` from file 12), so a bad
            bound is a 400 before file 13 runs (D7).
    *   **`prepareAgentProtocolBatchWrite`** stays pure. It validates with
        file 13, checks the `today` bound (`today_out_of_range`), sorts each
        rule's `times` and `weekdays` (D7), and encodes each `rule` and
        `period` through the codecs (`rule_format`, `period_format`). A
        `period` with no cycle and no Pause is stored as null. Soft warnings
        go to the response's top-level `warnings`.
    *   **The store's `writeProtocolBatch`** does everything that needs
        stored data, inside its transaction, so REST and MCP share it:
        *   it reads the stored Protocols, members and versions the request
            touches, in one query each;
        *   it rejects a Schedule id that already exists
            (`schedule_version_exists`), and a Schedule whose member isn't
            in its Protocol (`schedule_member_not_found`);
        *   for `archived: true`, it sets `deleted_at` to the current time and
            `archived_on` to `today`, or keeps both for a row already
            archived; `archived: false` on an archived member is
            `archived_row_not_restorable`;
        *   it inserts re-dated copies on a start move, from what was stored
            before the request, before dating the request's versions (D1);
        *   it assigns each Schedule version's `effective_from` by D1.

        The sorting happens in `prepareAgentProtocolBatchWrite`, before the
        rule is encoded, not in the store. The stored rule is the same
        either way, and the pure step is where the rule is still an object.

        As built in Phase 2, the copies differ from D1 (it copies on a later
        move, copies every member that undo didn't tombstone, skips a copy
        whose source already starts on the new date, and drops a copy when
        an edit is dated on the same day), an archived Protocol can still be
        edited, and `rule` and `period` are stored as objects. File 34a
        brought all three to this spec.
    *   **Reads** return the new shape, with `versions` and `currentVersion`
        (D6).
    *   **Doses:**
        *   writes accept an optional `timezoneOffsetMinutes`, which wins over
            `timezone`; without it, the offset is derived from an IANA
            `timezone` and `tookAt` through file 30;
        *   the `timezone` description says it is a display label;
        *   reads return `timezoneOffsetMinutes`.
    *   **The Effect read** gains an optional `timezoneOffsetMinutes`
        (default 0), an integer from −720 to +840; outside that it returns
        400 (D2). It builds its Effect window bounds with
        `effectBoundsFromLocalDates` instead of parsing `start_date`. The
        conversion happens in the Protocol source branch of the Effect
        handler, which passes instants on. `deriveEffectWindow` keeps taking
        instants and is unchanged, because the m29 Effect-window vectors pin
        its instant-based input in both languages.
    *   The pass-throughs of a supplied `deletedAt` (~519, ~566, and the
        Protocol's own at ~1381-1394 and the member's at ~1416, ~1430) are
        removed.

##### 30. `apps/server/src/timezone.ts` (Create), `apps/server/src/agent-plan-materialize.ts` and `apps/server/src/agent-workout-batch-write.ts` (Modify)

*   **Proposed Changes**:
    *   **The shared module exports two functions:**
        *   `localDateInTimezone(instant: Date, timeZone: string): string | null`;
        *   `offsetMinutesInTimezone(instant: Date, timeZone: string): number | null`.

        Both use one `Intl.DateTimeFormat` formatter, and both return `null`
        for an unknown zone or an invalid `Date`.
    *   `agent-plan-materialize.ts` imports it in place of its copy.
    *   `agent-workout-batch-write.ts` imports it, and keeps its fallback to
        the UTC date at its own call site, parsing its string input to a
        `Date` first.

    Neither caller changes behavior.

##### 31. `apps/server/test/observability.test.mjs` (Modify)

*   **Proposed Changes**: A test that scrubbing a logged Agent Protocol write
    and a logged Schedule write leaves none of `period`, `rule`,
    `startLocalDate`, `endLocalDate` or `today`. The deny-list already covers
    their parent keys, so `apps/server/src/observability.ts` changes only if
    this test fails. It did fail for `today`, which sits at the top level of
    the request rather than under a denied parent, so `today` joins the
    deny-list.

##### 32. Generated contract (Regenerate), plus one hand edit

*   **Files**:
    *   `packages/contract/openapi.json`
    *   `packages/contract/src/agent-client.ts`
    *   `apps/mobile/lib/api/perennia_api_client.dart`
    *   the generated command-map block of `agent-skills/perennia/references/api-operations.md`
*   **Proposed Changes**: `pnpm --filter @perennia/contract generate` output,
    committed. The hand-written example in `api-operations.md` (outside the
    generated block, around "frequency": "daily") is rewritten with a `rule`,
    local-date bounds and a top-level `today`.

##### 33. `CONTEXT.md` (Modify)

*   **Proposed Changes**:
    *   Rewrite **Schedule**, and add every term marked "yes" in
        [New and changed terms](#new-and-changed-terms). Planned dose and Day
        Status are marked "derived, never stored".
    *   Reword **Protocol** ("each with an optional Schedule") to refer to its
        Protocol Members and its Protocol Period.

##### 34. Tests (Create/Modify)

*   **New:**
    *   `apps/mobile/test/data/protocol_plan_migration_test.dart` (Create):
        *   schema 60 → 61 on a seeded database that has pending, deferred
            and quarantined rows for the four tables;
        *   Compounds and Doses survive unchanged;
        *   the four plan tables, and those rows, are gone;
        *   nothing is pending sync, and the foreign key check is clean;
        *   the upgraded schema equals `AppDatabase.inMemory()`'s, as
            `routine_plan_migration_test.dart` checks.
*   **Repository and sync behavior:**
    *   `apps/mobile/test/features/protocols/protocols_repository_test.dart`
        (Modify):
        *   a changed edit inserts a version, two the same day insert two,
            and an unchanged save inserts none;
        *   the first version's date for a member created with the Protocol,
            and for one added mid-course;
        *   start moves, both ways;
        *   a null draft inserts `unscheduled`;
        *   removing a member freezes `archived_on` and leaves its versions;
        *   undo tombstones the inserted version;
        *   unsorted times and weekdays are stored sorted, and an
            `as_needed` draft stores no amount;
        *   `logDoses` is all-or-nothing;
        *   the offset is written from the local time, and re-frozen on edit;
        *   a Dose image without the offset applies with null;
        *   an old-shape protocol image is quarantined;
        *   the Effect window comes from local-date bounds.
    *   `apps/mobile/test/features/protocols/protocol_screen_test.dart`
        (Modify): the period, Pause and rule editors; "No schedule"; the "N
        doses" helper; the editor showing `currentVersion` for a future
        start; validation messages; ≥ 48 dp targets.
    *   `apps/mobile/test/data/portable_archive_repository_test.dart`
        (Modify): a schema-60 archive imports its Compounds and Doses and
        skips its plan rows and their Activity Log rows.
    *   `apps/mobile/test/features/protocols/effect_screen_test.dart`
        (Modify): the notice shows only for a cycle or Pauses.
    *   `apps/mobile/test/tool/test_data_generator_test.dart`: see file 26.
*   **Server:**
    *   `apps/server/test/agent-protocols.test.mjs` (Modify):
        *   D7 rejects and warnings;
        *   `frequency` and `deletedAt` rejected by `.strict()`;
        *   `effectiveFrom` assigned by D1, and a reused Schedule id
            rejected;
        *   `archived: true` stamps the time and sets `archivedOn`;
        *   a `today` more than one day from the server's UTC date rejected;
        *   Dose offset precedence and derivation;
        *   the Effect read with and without `timezoneOffsetMinutes`, and
            400 for −721 and +841;
        *   a non-date `startLocalDate` rejected with 400;
        *   unsorted `times` and `weekdays` stored sorted.
    *   `apps/server/test/sync-convergence.test.mjs` (Modify): two devices
        insert same-day versions offline. Both rows reach both devices, and
        both pick the larger id. A version-1 request is rejected.
*   **Existing tests that this phase breaks** (Modify):
    *   every file under `apps/server/test/` that hard-codes
        `protocolVersion: 1` (`git grep -l "protocolVersion: 1"
        apps/server/test`): import `SYNC_PROTOCOL_VERSION` instead;
    *   `apps/mobile/test/api/perennia_api_client_test.dart`: use
        `syncProtocolVersion`;
    *   `routine_plan_migration_test.dart`, `workout_template_migration_test.dart`
        and `workout_template_group_migration_test.dart` (in
        `apps/mobile/test/data/`): replace the hard-coded schema 60 with
        `AppDatabase.inMemory().schemaVersion`;
    *   the tests that use `ScheduleFrequency`, `ProtocolDraft(startDate:…)`,
        `frequency` or `start_date` move to the new shapes:
        *   in `apps/mobile/test/`: `domain/protocols/protocols_domain_test.dart`,
            `domain/protocols/protocol_validation_test.dart`,
            `domain/effect_window_golden_test.dart`,
            `data/effect_repository_test.dart`, `data/erase_all_data_test.dart`,
            `features/protocols/effect_controller_test.dart`,
            `features/sync/sync_repository_test.dart`,
            `features/sync/sync_missing_metric_reference_test.dart`,
            `features/sync/sync_metrics_push_test.dart` and
            `features/sync/sync_default_measurements_test.dart`;
        *   in `apps/server/test/`: `agent-protocols.test.mjs`,
            `protocols-lifecycle-sync.test.mjs`, `protocols-sync.test.mjs`
            and `effect-window.golden.test.mjs`.

##### 34a. Rules settled after Phase 2's build (Modify)

This entry is lettered so the numbers of every later file stay as they were.
It changes what Phase 2's pull request built, so it lands as its own pull
request after that one, and before Phase 3, whose Planned list reads the
plan these rules shape.

*   **Files**:
    *   `apps/mobile/lib/domain/protocols/protocol_plan_days.dart` and
        `apps/server/src/protocol-plan.ts`: in `planDays` (and Dart's
        `endDateForDoseCount`), an every-N or cycle anchor with
        `anchor_is_default: true` is read as the Protocol's
        `startLocalDate` (D4).
    *   `apps/mobile/lib/data/repositories/training_repositories.dart`:
        *   `_redateVersionsForStartMove` follows D1. It copies nothing on a
            later move. On an earlier move it copies, for each member row of
            the Protocol that undo didn't tombstone (archived ones and ones
            this save removes included), the earliest version when that
            version is dated on or before the old start and after the new
            one.
        *   `_sameScheduleVersion` ignores the stored date of a default
            anchor, so an unchanged save after a start move inserts
            nothing (D1).
    *   `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart`:
        the editor loads a default every-N or cycle anchor as the
        Protocol's start, not the stored date, so it shows what is planned
        (D4).
    *   `apps/server/src/agent-protocols.ts`:
        *   the start-move copies in `finalizeProtocolPlanRows` follow the
            same D1 rule as the app. The skip for a source that already
            starts on the new date, and the step that drops a copy when an
            edit is dated on its day, are removed: neither case can arise
            once later moves copy nothing (D1, "No ties");
        *   a write that names a stored archived Protocol is refused with
            `protocol_archived` (D6). The member rules are unchanged;
        *   `rule` and `period` are stored as JSON text, the codec's
            encoding (Data shapes). The readers keep accepting an object;
        *   the `startLocalDate` description says that moving the start
            earlier copies the versions of the members planned from the
            old start, and that default anchors follow the start.
    *   Generated contract, as file 32, for the changed descriptions.
    *   The two m36 vector files, for the cases below.
*   **Vectors to add** (each with a `note`):
    *   in `m36-protocol-plan.json`:
        *   `default-every-n-anchor-reads-the-start`: every 2 days, default
            anchor stored as 2026-09-01, start 2026-09-04. 2026-09-04 and
            2026-09-06 are planned and 2026-09-05 is `not_scheduled_today`.
            Counted from the stored date, 2026-09-04 would not be planned;
        *   `default-anchor-on-a-later-version-follows-the-start`: start
            2026-09-04, a daily version from 2026-09-01 and an every-2-days
            version from 2026-09-10 whose default anchor stores 2026-09-01.
            2026-09-10 is planned and 2026-09-11 is not;
        *   `default-cycle-anchor-reads-the-start`: 3 on and 2 off, default
            anchor stored as 2026-09-01, start 2026-09-05. 2026-09-05 is
            on (cycle day 0), where the stored date would make it day 4, off;
        *   `start-moved-later-needs-no-copy`: the versions of
            `start-moved-later-past-an-edit` without its copy give the same
            PlanDays;
        *   `start-moved-earlier-keeps-a-mid-course-member-to-its-first-date`:
            the start moved from 2026-10-10 to 2026-10-05. Member A, planned
            from the old start, has a copy dated 2026-10-05; member B, added
            on 2026-10-12, has none. B reads `removed` from 2026-10-05 to
            2026-10-11 and is planned from 2026-10-12;
        *   `start-moved-earlier-extends-an-archived-member`: a member
            planned from the old start 2026-10-10 and archived on
            2026-10-15, with a copy dated 2026-10-05, is planned from
            2026-10-05 through 2026-10-15 and reads `removed` after;
        *   `every-n-days-user-anchor-before-the-start` (exists) pins that a
            user-set anchor is read as stored;
    *   in `m36-protocol-plan-validation.json`:
        *   `as-needed-rule-with-a-blank-amount-entered-rejects`:
            `amountEntered` of `"  "` and nothing else →
            `[amount_absent]` (D7).
*   **Tests:**
    *   `apps/mobile/test/domain/protocol_plan_dose_count_test.dart`: an
        every-N rule whose default anchor stores another date counts from
        `startLocalDate`.
    *   `apps/mobile/test/features/protocols/protocols_repository_test.dart`:
        *   moving the start later inserts no version;
        *   moving it earlier copies a member planned from the old start, an
            archived one, and one the same save removes, but not a member
            added mid-course or one with no versions;
        *   after a later start move, an unchanged save of a member whose
            current version has a default every-N anchor inserts nothing.
    *   `apps/mobile/test/features/protocols/protocol_screen_test.dart`: a
        default anchor whose stored date is an old start shows the current
        start.
    *   `apps/server/test/agent-protocols.test.mjs`:
        *   the same start-move cases through the Agent write;
        *   a write naming an archived Protocol is refused with
            `protocol_archived`; re-sending an archived member with
            `archived: true` is accepted and keeps its stamp; `archived:
            false` on it is refused with `archived_row_not_restorable`;
        *   an Agent Schedule equal to the current version is inserted (D6);
        *   `rule` and `period` are stored as JSON text, and a row stored as
            an object still reads.
*   **As built.** File 34a's build made these choices where the entry above
    was silent. Each is now stated where it applies:
    *   `scheduleDaysFromStart` and `protocolCycleFromStart`, which read a
        default anchor as the start, are public in `protocol_plan_days.dart`.
        `planDays`, the repository and the editor share them, so D4 has one
        reading in Dart. The repository's private
        `_plannedProtocolCompoundQuery` holds the "every member row except
        undo tombstones" predicate the start move uses.
    *   The app's Protocol-row comparison, `_canonicalPeriodColumn`, reads a
        default cycle anchor as the start too (D1, "Saves that change
        nothing").
    *   A copy, and the period on any start move, store the new start in a
        default anchor (D1, D4). A tie on the earliest date copies the
        larger id (D1).
    *   A copy of a row an Agent stored as an object in Phase 2 is written
        as JSON text. The source row is left as it is (Data shapes).
    *   The Agent path sorts in `prepareAgentProtocolBatchWrite` (file 29).
    *   A Protocol tombstoned by undo is refused with
        `archived_row_not_restorable`, and the member and Schedule checks
        run beside a Protocol's refusal (D6).
    *   The existing vector `start-moved-later-past-an-edit` was left as
        it was. Its input still plans correctly, but its `note` still calls
        `ver-x-3` a copy, which no writer makes any more. File 40a rewrites
        the note.
    *   Two review findings were left as spec gaps, and are now settled in
        D1: a member archived before its earliest version (file 40a stops
        copying it), and a mid-course member after a later move and then an
        earlier one (a known limit).

#### Phase 3: the Planned list

##### 35. `apps/mobile/lib/data/repositories/protocol_plan_repository.dart` (Create) and `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify, Phase 3 part)

*   **Type / Scope**: A `part of 'training_repositories.dart'`, laid out like
    `apps/mobile/lib/data/repositories/routine_up_next_repository.dart`.
*   **Proposed Changes**:
    *   **Class:** `ProtocolPlanRepository`, reached as
        `TrainingRepositories.protocolPlan`. The main file gains
        `part 'protocol_plan_repository.dart';` and a `late final
        protocolPlan`, wired like `routineUpNext`.
    *   **What it builds:** `PlanProtocol`s and `PlanDose`s from Drift. It
        leaves out rows tombstoned by undo, and keeps archived rows with their
        `archived_on`.
    *   **Phase 3 adds** `watchPlannedDay(localDate, {required today})
        -> Stream<PlannedDay>`. `PlannedDay` holds the day's `DayStatus`es
        and `PlanDay`s, plus each Compound's and Protocol's record, for the
        rows.
        *   **Its public types, as built.** `PlannedDay` carries
            `localDate`, `today`, `day` (below), `planDays`, `dayStatuses`,
            and by id the full `CompoundRecord` of each Compound planned
            that day and the `ProtocolOptionRecord` of each Protocol,
            archived ones included. It derives `isToday`, `isFuture` and
            `groups`, the Planned list's rows in D6's order.
            *   A `PlannedRowGroup` is one Protocol and its `PlannedRow`s.
            *   A `PlannedRow` holds `protocolId`, `compoundId`, `slot`,
                `plannedLocalTime` (null when untimed), the planned
                `PlanAmount` and a `PlannedRowStatus`.
            *   `PlannedRowStatus` is `logged`, `pending` or `notLogged`
                (D6's three labels), or `none` on a future day, whose rows
                show no label.
        *   `today` is the caller's local date, read from its clock. The
            repository never reads a clock, and a required parameter means
            no caller can forget it. It decides "Pending" against "Not
            logged" and whether the day has Day Statuses at all.
        *   `PlannedDay` also carries the day's `ProtocolDayRecord`: the
            Doses its Day Statuses were matched against. The stream reads
            them through `ProtocolsRepository.watchProtocolDay`, the same
            watch the day's log shows, so the view reads one stream and the
            log and the Planned list can't disagree for a frame.
        *   The stream re-emits when a Protocol, Protocol Member, Schedule
            Version, Compound or Dose changes. It doesn't re-emit when
            midnight passes; the view rebuilds with a new `today` instead
            (D6, "The day boundary").
        *   A future day has no Day Statuses. Its rows come from the same
            matching run over its PlanDays with no Doses, so a slot is
            numbered the same way on every day.
    *   **Phase 3 also adds** a one-shot `plannedDay(localDate, {required
        today}) -> Future<PlannedDay>`, the same read once. "Log all
        planned" uses it to act on what is stored when it runs, not on a
        rendered snapshot.

##### 36. `apps/mobile/lib/features/protocols/widgets/protocols_day_view.dart` (Modify)

*   **Proposed Changes**:
    *   **The Planned list,** above the logged Doses, driven by
        `watchPlannedDay`. Its rows, labels and "Log all planned" follow D6,
        and a future day follows D6 too.
    *   **`LogDoseSheet`** gains optional constructor parameters:
        `initialDate`, `initialTime`, `plannedAmount` (`amountValue`,
        `amountEntered`, `unit`), `plannedRoute` and `protocol`.
        *   The prefill of the time from the last Dose is removed, and the
            time defaults to D6's rule. As built, the method that set the
            prefill, `_seedTookAt`, keeps its name and now computes D6's
            default.
        *   The time picker gains a date field.
        *   `LogDoseSheet.edit` lets the date change.

##### 37. `apps/mobile/lib/features/protocols/controllers/protocols_day_controller.dart` (Modify)

*   **Proposed Changes**: Exposes the planned-day stream. "Log all planned"
    takes the rows from `dueUnfilled(…, today, now)` and calls
    `ProtocolsRepository.logDoses` once, with each row's planned amount,
    unit and route, tagged with its Protocol and timed now.
    *   **The clock.** A new `protocolsClockProvider`
        (`Provider<DateTime Function()>`, `DateTime.now` by default) is the
        one clock of the Protocols logging surfaces, injectable in tests
        like `syncNowProvider`. The selected Protocol Day's default, the
        log sheet's time default and "Log all planned" all read it.
    *   **The day boundary.** The controller keeps the `today` its build
        read. `refreshIfDayChanged()` rebuilds when the clock's local date
        differs from it; the view calls it once a minute and on resume
        (D6).
    *   **"Log all planned"** reads today's plan with the one-shot
        `plannedDay` (file 35). An empty `dueUnfilled` writes nothing. A
        call made while another is in flight shares that call (D6).
        *   As built, it builds every Dose before it writes any. A due row
            whose Compound, amount, unit, route or Protocol is missing from
            the `PlannedDay` throws a `StateError`, so nothing is written.
            D7's `amount_required` and the member's live Compound make that
            a broken invariant, not a user error, and one Batch is never
            partly logged.

##### 38. `apps/mobile/lib/features/protocols/widgets/compound_list_screen.dart` (Modify, Phase 3 part)

*   **Proposed Changes**: Opens `LogDoseSheet` (~342) with `initialDate` set
    to the Protocol Day the list was opened for, so a past day defaults to
    12:00 on that date.
    *   **Which day.** Opened from the Protocol Day view's add button, that
        is the selected Protocol Day. Opened from Library or Settings, it is
        today. The list reached from Library or Settings is the 2-tap repeat
        path, and the selected Protocol Day outlives the view that set it:
        logging on whatever day was last browsed would back-date a Dose
        the user means to log now.
    *   Phase 3 reads `selectedProtocolDayProvider` on every route, so the
        list from Library or Settings opens on the last browsed day. File
        40a changes it.

##### 39. `apps/mobile/lib/l10n/app_en.arb` and generated `app_localizations*.dart` (Modify/Regenerate)

*   **Proposed Changes**: Strings for:
    *   the Planned list's three row labels, "Any time" and "Log all planned";
    *   the log sheet's date field label;
    *   the seven Day Status labels;
    *   the five not-planned reasons: "Not scheduled that day", "As needed",
        "No schedule", "Removed" and "Outside the Protocol's dates". The
        first reads right on any date, past ones in the Consistency view
        included (CUJ 6). (Phase 3 wrote "Not scheduled today"; changed
        after Phase 4's review.)

    No string uses a word D6 bans. The Planned list has no heading string
    (D6). The Day Status and reason strings land in Phase 3 but nothing
    shows them until Phase 4 (file 41).

##### 40. Tests (Create/Modify)

*   `apps/mobile/test/features/protocols/protocols_day_view_test.dart`
    (Modify):
    *   the Planned list's labels;
    *   "Log all planned" leaving a later row Pending (CUJ 1);
    *   no bulk action on past days, and no actions on future days;
    *   two-tap logging from a row;
    *   the date field;
    *   labels present alongside color;
    *   contrast in both themes;
    *   a double tap on "Log all planned" logs the due rows once, and
        moving the clock past midnight turns today's rows into "Not
        logged" and removes the bulk action (both on a real in-memory
        database, through `protocolsClockProvider`).
*   `apps/mobile/test/features/protocols/log_dose_sheet_test.dart` (Modify):
    the prefill rules on today, past and future days, and a date change on
    edit.
*   `apps/mobile/test/features/protocols/protocol_plan_reopen_test.dart`
    (Create): the app is killed during "Log all planned". After reopening, the
    Batch is either fully applied or absent, and the Planned list matches.
*   `apps/mobile/test/features/protocols/compound_list_screen_test.dart`
    (Modify): the sheet opens on the selected Protocol Day.

##### 40a. Rules settled after file 34a's and Phase 3's builds (Modify)

This entry is lettered so the numbers of every later file stay as they were.
It changes what file 34a and Phase 3 built, so it lands as its own pull
request after Phase 3's. Nothing in Phase 4 depends on it, but it should
land before Phase 4's Consistency view shows these Doses.

*   **Files**:
    *   `apps/mobile/lib/data/repositories/training_repositories.dart`:
        *   `_redateVersionsForStartMove` skips a member whose
            `archived_on`, as stored before the save, is before its earliest
            version (D1, "A member removed before it planned anything").
        *   `editDose`: when the time changes on a Dose with a
            `timezoneOffsetMinutes`, the new time is read at that offset,
            which is kept, and only the local date is frozen again from it.
            The timezone label is kept too. A Dose with a null offset is
            frozen again from the device's zone, as today (D6). A draft
            that names its own `localDate` or `timezone` still takes
            precedence; the edit sheet names neither when the moment
            changes.
    *   `apps/server/src/agent-protocols.ts`: the start-move copies in
        `finalizeProtocolPlanRows` skip the same members.
    *   `apps/mobile/lib/features/protocols/widgets/protocols_day_view.dart`:
        *   a "Logged" Planned list row opens `LogDoseSheet.edit` on the
            Dose that fills it. `PlannedRow` has no `doseId`, so the row's
            fill is found in the `PlannedDay`'s `dayStatuses` by Compound,
            Protocol and slot, and its Dose by that fill's `doseId` in the
            `PlannedDay`'s `ProtocolDayRecord`. "Pending" and "Not logged"
            rows keep opening a new log (D6);
        *   `LogDoseSheet.edit` shows and edits the Dose's date and time at
            its frozen offset, and the day's Dose rows show their time the
            same way, so a row and its edit sheet agree (D2, D6). A Dose
            with a null offset reads in the device's zone, as today. The
            sheet holds a clock reading at the offset and turns it into the
            moment on Save, sending no `localDate` or `timezone` when the
            moment changed. Its date picker reads "today" at the offset
            too (D6, "The log sheet").
    *   `apps/mobile/lib/features/protocols/widgets/compound_list_screen.dart`:
        `CompoundListScreen` gains an optional `protocolDay`. The Protocol
        Day view's add button passes the selected Protocol Day. Library and
        Settings pass nothing, and the sheet then opens on today (file 38).
    *   `packages/golden-vectors/vectors/m36-protocol-plan.json`: the
        `note` of `start-moved-later-past-an-edit` says that `ver-x-3` is
        an equal version dated on the new start, as a writer before file
        34a or an Agent could store, and that it plans the same as
        `start-moved-later-needs-no-copy`. The input and expected output
        don't change.
*   **Tests:**
    *   `apps/mobile/test/features/protocols/protocols_repository_test.dart`:
        moving the start earlier gives no copy to a member archived before
        its earliest version, and still gives one to a member the same save
        removes; editing the time of a Dose logged at another offset keeps
        that offset and freezes the local date from it.
    *   `apps/server/test/agent-protocols.test.mjs`: the same start-move
        case through the Agent write.
    *   `apps/mobile/test/features/protocols/protocols_day_view_test.dart`:
        tapping a "Logged" row opens that Dose for edit, and saving it adds
        no Dose; a Dose logged at another offset shows its own clock time.
    *   `apps/mobile/test/features/protocols/log_dose_sheet_test.dart`: the
        edit sheet shows a Dose's time at its frozen offset, and its date
        picker ends at today at that offset, for a western and an eastern
        offset.
    *   `apps/mobile/test/features/protocols/compound_list_screen_test.dart`:
        opened as from Library after browsing a past day, the sheet opens on
        today; opened from the Protocol Day view, on the selected day.
*   **Not in this entry:** nearest-time matching, and the time a Dose
    logged from the Planned list is logged at. Both stay as built (Open
    Questions). Two findings from its review land in file 46a instead,
    because they touch files this entry doesn't list: the clock-at-offset
    arithmetic copied in three places, and the order of the day's Dose
    rows.

#### Phase 4: the Consistency view

##### 41. `apps/mobile/lib/features/protocols/widgets/consistency_screen.dart` (Create)

*   **Proposed Changes**:
    *   Opens for one Compound, or for a Protocol with a tab per member.
        Each tab is that Compound's own Consistency across every Protocol
        it is in (D6, "Tabs").
    *   A range picker: the last 30 days (including today) by default; 7, 90
        or 365 days; or a custom range up to 366 days. A custom range ends
        at today at the latest, its picker starts at 2000-01-01, and a
        longer pick keeps its last 366 days. The chosen dates are written
        out under the picker (D6, "The range").
    *   The chart (file 42) above a day list. Each day shows its Day Status
        label and reason, the logged times and amounts, and the planned times
        and amounts, as D6 describes ("The day list", "Amounts").
    *   It shows `EffectScreen.disclaimerText`.
    *   It doesn't rebuild when local midnight passes (D6, "The day
        boundary").
    *   **Strings.** New `app_en.arb` strings, with the generated
        `app_localizations*.dart` regenerated: the "Consistency" button and
        the screen title, the range presets and "Custom", "Planned",
        "Extra" and the extra count, the lines for a Compound in no
        Protocol, for no Doses, for an empty chart and for a load error,
        the chart's three legend entries and its semantics label. The Day
        Status, not-planned reason and Planned list row strings of file 39
        are reused. No string uses a word D6 bans. (The arb files are not
        in this phase's list of files; settled after Phase 4's build.)

##### 42. `apps/mobile/lib/features/protocols/widgets/consistency_chart.dart` and `apps/mobile/lib/features/protocols/models/consistency_chart_data.dart` (Create)

*   **Proposed Changes**: An `fl_chart` chart drawn as a scatter. X is the
    date and Y is the time of day.
    *   **Why a `LineChart`.** `fl_chart`'s `ScatterChart` draws points
        only, with no segments and no shaded ranges. So the chart is a
        `LineChart`: the Doses are a series of dots with no line, each
        planned segment is a two-point line, and the shaded runs are
        ranges painted behind the plot. (Settled after Phase 4's build.)
    *   Each logged Dose is a point; an extra is a ring, read from
        `ConsistencyRange.extraDoseIds` (file 44).
    *   Each planned time is a horizontal segment over the days it applies.
    *   Untimed planned doses are drawn as a band labelled "Any time" along
        the top.
    *   Off-cycle and paused days are shaded and labelled, as D6
        ("Shading") describes: one shade, hatched for off cycle, a marker
        under every run, the run's word when it is at least 56 px wide,
        and matching legend swatches.

    The model is pure and tested, following
    `apps/mobile/lib/features/protocols/models/effect_timeline_chart_data.dart`.
    It is built once per `ConsistencyRange` the repository emits, not on
    every widget build.

##### 43. `apps/mobile/lib/features/protocols/controllers/consistency_controller.dart` (Create)

*   **Proposed Changes**: The range state and the `watchConsistency` stream.
    *   The range state is in memory only and auto-disposed with the view,
        so the view opens on the default again. It reads "today" from
        `protocolsClockProvider` (file 37) when built and on every pick,
        and passes it to `watchConsistency`.
    *   A custom pick is clamped before it reaches the repository: an end
        after today becomes today, and a range longer than
        `maxConsistencyRangeDays` (366) keeps its last 366 days.
    *   The controller exposes `mounted`. The custom picker reads the
        controller before its dialog opens and checks `mounted` after,
        because the picker's own `ref` can be disposed by a remount while
        the dialog is open.

##### 44. `apps/mobile/lib/data/repositories/protocol_plan_repository.dart` (Modify, Phase 4 part)

*   **Proposed Changes**: Adds `watchConsistency(compoundId, from, to,
    {required today}) -> Stream<ConsistencyRange>`: the range's `PlanDay`s
    for the Compound, its `DayStatus`es (none after `today`) and its
    non-archived Doses.
    *   **`today`** is required and named, as on `watchPlannedDay` (file
        35): it is the caller's local date, read from its clock, and the
        repository never reads a clock. (File 44 first named no `today`;
        settled after Phase 4's build.)
    *   **Range limits.** It throws an `ArgumentError` when `from` is
        after `to`, or when the range holds more than
        `maxConsistencyRangeDays` (366) days, both ends included. The
        controller clamps a pick first (file 43), so the view never
        throws.
    *   **What it reads.** Every Protocol the Compound is a member of,
        each narrowed to that Compound's members before `planDays` runs,
        so only that Compound's PlanDays are planned. Its Day Statuses are
        the ones a read of the whole plan would give, because a Day Status
        is one per Compound and date. It re-emits when a
        Protocol, Protocol Member, Schedule Version, Compound or Dose
        changes, like `watchPlannedDay`.
    *   **`ConsistencyRange`** carries the PlanDays, Day Statuses and
        Doses, the Compound's record (for a planned amount's strength,
        D6 "Amounts") and each Protocol's record. It derives the day list
        (`days`, newest first, D6 "The day list") and `extraDoseIds`, the
        one reading of an extra that the chart and the day list share.
    *   **`sequence` per Compound and date.** `_planDoses` numbers each
        Dose's `sequence` among its Compound's Doses on its local date, as
        D6 step 2 and `PlanDose` define it. Phase 3 numbered it per
        Compound only, which is the same on a one-day read, so the
        Planned list numbers exactly as before. A range read needs the
        per-date numbering. (Settled after Phase 4's build.)

##### 45. `apps/mobile/lib/features/protocols/widgets/compound_list_screen.dart` and `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart` (Modify, Phase 4 part)

*   **Proposed Changes**: Each Compound row gets a "Consistency" icon button
    (≥ 48 dp). The Protocol screen gets a "Consistency" button. Both open file
    41.
    *   Both push the view wrapped in its own `ProtocolsLockGate` (D6,
        "The lock").
    *   The Protocol screen's button shows only when editing a saved
        Protocol that has members. It opens a tab per member in member
        order, read from the Protocol as saved (D6, "Tabs").

##### 46. Tests (Create)

*   `apps/mobile/test/features/protocols/consistency_screen_test.dart`: labels
    and reasons, the range picker, both entry points, and none of the words D6
    bans. Text contrast and tap targets are checked on both entry points in
    both themes, the Protocol view's tabs included.
*   `apps/mobile/test/features/protocols/consistency_chart_data_test.dart`:
    planned segments across a version change (CUJ 6), the untimed band, and
    shading (CUJ 3 and 5).
*   `apps/mobile/test/performance/performance_budgets_test.dart` and
    `apps/mobile/test/performance/performance_budget_thresholds.dart`
    (Modify): a budget for `planDays` plus `dayStatuses` over 366 days for one
    Compound in 3 Protocols. It has 5 versions per Protocol and 800 Doses, and
    must finish under 50 ms.
*   `apps/mobile/test/performance/README.md` (Modify): a row for that
    budget, beside the other budgets' rows. (Not in this list before
    Phase 4's build; settled after it.)

##### 46a. Findings settled after file 40a's and Phase 4's builds (Modify)

This entry is lettered so the numbers of every later file stay as they were.
It changes what file 40a and Phase 4 built, so it lands as its own pull
request after Phase 4's. Nothing in Phase 5 depends on it.

*   **Files**:
    *   `apps/mobile/lib/domain/protocols/protocols.dart`: one pure helper
        for a Dose's clock reading where it was taken: an instant at a
        nullable frozen offset, as a UTC `DateTime` whose fields are that
        clock, or the device's zone when the offset is null.
        `DoseRecord` exposes it as a getter, and `DoseRecord.localTime`
        formats it. Today the same arithmetic is written three times:
        `DoseRecord.localTime`, `_doseClock` in `protocols_day_view.dart`,
        and the local-date step of `editDose` in
        `training_repositories.dart`. A fix to one would leave the others
        reading a Dose differently, which is the disagreement between a
        row and its edit sheet that file 40a removed. No behavior changes.
        *   **Names.** The helper is
            `clockAtOffset(DateTime instant, int? timezoneOffsetMinutes)`,
            and the getter is `DoseRecord.clock`. (Settled after file
            46a's build.)
    *   `apps/mobile/lib/features/protocols/widgets/protocols_day_view.dart`:
        `_doseClock` is removed, and the day's Dose rows and the edit
        sheet read the helper. A fourth copy of the arithmetic, the edit
        sheet's `_pickDate` "today" (D6, "The log sheet"), reads it too,
        with the same behavior. (Settled after file 46a's build.)
    *   `apps/mobile/lib/data/repositories/training_repositories.dart`:
        *   `editDose` reads the helper to freeze the local date at the
            Dose's offset.
        *   `watchProtocolDay` lists the day's Doses in clock order: the
            helper's clock, date and time to the minute, then id. That is
            matching's order (D6 step 2) whenever every clock falls on the
            Protocol Day; D6, "The day's Dose rows", says where it differs
            and why the date leads. The query keeps its instant order, and
            the rows are sorted after the read, because the clock depends
            on each row's offset. Doses logged at different offsets on one
            Protocol Day then read in clock order. The comparator,
            `_compareDosesByClock`, is shared with the Consistency read.
        *   Matching's own order is unchanged: `_planDoses` in
            `protocol_plan_repository.dart` still sorts by `HH:MM`, then
            id, because D6 step 2 and the m36 vectors define it. (Settled
            after file 46a's build.)
    *   `apps/mobile/lib/data/repositories/protocol_plan_repository.dart`:
        the Consistency read's Doses (`watchConsistency`, which reads them
        through `ProtocolsRepository._activeDoseQuery` in
        `training_repositories.dart`) are sorted by frozen `localDate`
        first, because a range spans many dates, and then each date's by
        the day log's comparator, so a day list's Doses and extras read in
        clock order. The sort runs after the read and is a total order,
        so the query's own instant order never shows. (Settled after file
        46a's build.)
*   **Tests:**
    *   `apps/mobile/test/features/protocols/protocols_repository_test.dart`:
        two Doses on one Protocol Day, the later instant at an earlier
        clock time through its offset, are listed in clock order, by
        `watchProtocolDay` and by `watchConsistency`. Two Doses at the same
        clock minute through different offsets, with the larger id at the
        earlier instant, are listed in id order.
    *   `apps/mobile/test/features/protocols/protocols_day_view_test.dart`:
        the same two Doses show in clock order.
    *   The existing tests for the edit sheet's offset and for `editDose`
        pass unchanged. `consistency_screen_test.dart` is unchanged: the
        Consistency read's order is covered in the repository test.
        (Settled after file 46a's build.)
*   **Not in this entry:** the Consistency view's day boundary, which
    stays as built (D6, "The day boundary").

#### Phase 5: reminders

##### 47. `apps/mobile/pubspec.yaml` and `apps/mobile/pubspec.lock` (Modify)

*   **Proposed Changes**: Add `flutter_local_notifications`, `timezone` and
    `flutter_timezone`, at their current stable versions at implementation
    time.

##### 48. `apps/mobile/lib/features/protocols/services/protocol_reminder_plan.dart` (Create)

*   **Type / Scope**: Pure Dart.
*   **Proposed Changes**:
    `desiredReminders(inputs, now, {horizonDays = 14, cap = 48}) -> {reminders: List<ReminderSpec>, horizonEnd: LocalDate}`.
    *   **Eligibility (D5):** reminders-on Protocols only, unfilled timed
        planned doses only, future times only. One reminder per
        (date, time).
    *   **Horizon:** whole days only. Days are added in date order while the
        total stays at or under the cap, up to `horizonDays`, and
        `horizonEnd` is the last day added. The days are today through
        today + (`horizonDays` - 1), with today read from `now` in its zone.
        When today's own reminders exceed the cap, no day is added and
        `horizonEnd` is yesterday (D5, "Its days"). (Settled after Phase
        5's build.)
    *   **Instants:** a planned time becomes an instant in `now`'s zone. A
        time a spring-forward change skips is the first valid minute after
        the gap, and a time a fall-back change repeats is its first
        occurrence (D5, "Daylight-saving changes"). Distinct times inside
        one gap stay separate reminders. (Settled after Phase 5's build.)
    *   **Ids:** `ReminderSpec.id = -(daysBetween(2000-01-01, localDate) * 1440 + minuteOfDay) - 1`,
        a negative int32 for every date before 6000.

##### 49. `apps/mobile/lib/features/protocols/services/protocol_reminder_scheduler.dart` (Create)

*   **Proposed Changes**: The reminder reconciler, wrapping the plugin.
    *   **Start:** it initializes the plugin with every permission request
        turned off, and the timezone database with the local zone from
        `flutter_timezone`. The zone is read again on every run, and an id
        the database lacks falls back to a fixed zone at the phone's
        current offset (D5, "An unknown zone id"). (Settled after Phase 5's
        build.)
    *   **`reconcile()`** diffs `desiredReminders` against the pending
        notifications whose payload kind is `protocolReminder`, then cancels
        and schedules. It never calls `cancelAll`.
        *   The first run in the process, and any run whose zone differs
            from the last run's, schedules every wanted reminder again;
            other runs schedule only the missing ones (D5, "Rescheduling
            everything").
        *   It schedules only while the device switch is on, a Protocol has
            reminders on (D5), and the permission reads `granted`.
        *   A run that throws is caught and changes nothing; the next
            trigger runs again. (Settled after Phase 5's build.)
    *   **Notifications** use `zonedSchedule` with `inexactAllowWhileIdle`,
        title "Supplements", body "Planned for <localized time>", channel
        "Reminders", `VISIBILITY_PRIVATE`, and small icon `@mipmap/ic_launcher`.
        The time is `DateFormat.jm()` of the planned time (D5, "Text is
        always generic").
    *   **Triggers:**
        *   app start;
        *   resume, from `didChangeAppLifecycleState` in `apps/mobile/lib/app.dart`;
        *   Drift `tableUpdates` on `protocols`, `protocol_compounds`,
            `schedules` and `doses`, debounced 500 ms;
        *   a change of `lastSuccessfulSyncAt` from
            `SyncStatusRepository.watchStatus()`;
        *   the reminder status screen opening, and its device switch being
            flipped (file 58). (Settled after Phase 5's build.)
    *   **Start's permission read.** Only an `unsupported` answer (no
        notification system, as in tests) skips the plan-change and sync
        triggers. A first read that fails starts them anyway, and each run
        reads the permission again. (Settled after Phase 5's build.)
    *   **Runs:** one at a time, with a dirty flag for triggers that arrive
        during a run. When the device switch is off or no Protocol has
        reminders on, it cancels its own notifications and schedules none.
    *   **Exposes** the permission status (file 51) and `horizonEnd` for the
        UI.

##### 50. `apps/mobile/lib/data/repositories/protocol_plan_repository.dart` (Modify, Phase 5 part)

*   **Proposed Changes**: Adds `reminderInputs(from, to)`. It returns one
    `{protocolId, compoundId, localDate, localTime, remindersEnabled, filled}`
    per timed planned dose:
    *   `filled` for today comes from today's `DayStatus` fills;
    *   future dates come from `planDays` and are always unfilled;
    *   `remindersEnabled` comes from `PlanProtocol`.

    Phase 5 needed two more reads here, which this entry didn't list. Both
    live in the repository because repositories are the only layer that
    touches Drift (AGENTS.md):

    *   `watchReminderInputChanges()`: a `Stream<void>` over Drift
        `tableUpdates` on `protocols`, `protocol_compounds`, `schedules` and
        `doses`, the tables `reminderInputs` reads. It is the reconciler's
        plan-change trigger (file 49), which debounces it.
    *   `anyProtocolRemindersOn()`: whether any Protocol that isn't archived
        has `remindersEnabled` on. With `reminderInputs`, it gives "a
        Protocol has reminders on" (D5) for the banner (file 57).

    (Settled after Phase 5's build.)

##### 51. `apps/mobile/lib/features/training/services/timer_background_scheduler.dart`, `apps/mobile/ios/Runner/AppDelegate.swift` and `apps/mobile/android/app/src/main/kotlin/fit/perennia/app/MainActivity.kt` (Modify)

*   **Proposed Changes**: A read-only `notificationPermissionStatus()` on the
    `perennia/timer_background` channel, with a new `notDetermined` value in
    `TimerBackgroundPermissionStatus`.
    *   **iOS:** reads `UNUserNotificationCenter.getNotificationSettings`.
    *   **Android:** `NotificationManagerCompat.areNotificationsEnabled()`.
        On Android 13 and later, it reports `notDetermined` when the
        permission isn't granted and has never been requested.
        `MainActivity` records the first request in its `SharedPreferences`.
        *   **"Never requested"** means both no record of a request and no
            pending rationale (`shouldShowRequestPermissionRationale`).
            Android asks for a rationale after one denial, so a user an
            earlier build asked once, before the record existed, reads as
            `denied`. A user who declined twice under an earlier build
            still reads as `notDetermined`, because Android then shows no
            rationale and the record doesn't exist yet. Nothing has
            shipped, so this is accepted. (Settled after Phase 5's build.)
    *   Requesting still goes through `requestPermissionIfNeeded()`.

##### 52. `apps/mobile/lib/app.dart` (Modify)

*   **Proposed Changes**:
    *   Start the reminder reconciler after the first frame, next to
        `TimerNotificationRouter.start()`.
    *   **Routing a tap** (iOS `onProtocolReminderTapped` from the channel,
        Android the plugin's tap callback, and its launch details on a cold
        start): call `selectedProtocolDayProvider.select(localDate)`, then
        push `ProtocolsDayView.routeName`, which `ProtocolsLockGate` already
        wraps. When that route is already on top, it only selects the date
        and pushes nothing (D5, "Tap").
    *   **`apps/mobile/lib/features/training/services/timer_notification_router.dart`
        (Modify).** A method channel has one handler, and
        `TimerNotificationRouter` already owns `perennia/timer_background`'s.
        So the router gains an optional `onProtocolReminderTapped(String
        localDate)` callback and hands the iOS `onProtocolReminderTapped`
        call to it; `app.dart` passes a callback that parses the date and
        routes as above. The router's private top-route check becomes a
        shared `isTopRoute(navigator, routeName)`, which both taps use.
        (This file was not listed before; settled after Phase 5's build.)

##### 53. `apps/mobile/ios/Runner/AppDelegate.swift` (Modify, reminders)

*   **Proposed Changes**:
    *   **`didReceive`:** a response whose `userInfo["timerId"]` is present
        keeps today's timer handling. Otherwise, a response whose plugin
        payload has `kind == "protocolReminder"` sends
        `onProtocolReminderTapped(localDate)` over the timer channel, buffered
        until `signalReady` as timer taps are. Any other response is
        ignored. Nothing calls `super`, so the plugin never sees a tap on
        iOS, and D5's iOS routing says the same. (Settled after Phase 5's
        build.)
    *   **`willPresent`:** returns `[.banner, .list]` for a reminder. The timer
        keeps its current options (`[.banner]`), as does any other
        notification. Both `.banner` and `.list` need iOS 14, and the
        Runner target's deployment target is iOS 13.0; the existing
        `.banner` has no availability check either. File 60a guards them.
        (Settled after Phase 5's build.)
    *   The plugin needs no other registration than the existing
        `GeneratedPluginRegistrant`.

##### 54. `apps/mobile/android/app/src/main/AndroidManifest.xml` and `apps/mobile/android/app/build.gradle.kts` (Modify)

*   **Proposed Changes**:
    *   **Manifest:**
        *   register the plugin's `ScheduledNotificationReceiver` and
            `ScheduledNotificationBootReceiver`, the latter for
            `BOOT_COMPLETED` and `MY_PACKAGE_REPLACED`;
        *   add `RECEIVE_BOOT_COMPLETED`, and no exact-alarm permission.
    *   **Gradle:**
        *   in `compileOptions`, set `isCoreLibraryDesugaringEnabled = true`;
        *   add a `dependencies` block with
            `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:<version the plugin's README requires>")`.

##### 55. `apps/mobile/lib/features/settings/repositories/settings_repository.dart` (Modify)

*   **Proposed Changes**: A device-level `protocolRemindersOnThisDevice`
    (default true), stored in `settings.json` like `restTimerSoundsEnabled`
    and never synced. The UI's "Reminders on this device" switch, called the
    device switch in D5, is this setting.

##### 56. `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart` (Modify, Phase 5 part)

*   **Proposed Changes**: The Reminders switch, bound to `remindersEnabled`.
    *   Turning it on calls `requestPermissionIfNeeded()` the first time
        (CUJ 10): only when `notificationPermissionStatus()` reads
        `notDetermined` (D5, "The first time"). The reconciler's
        `requestPermissionIfNotAsked()` makes that check, then runs. A
        denial leaves the switch on. (Settled after Phase 5's build.)
    *   Next to it: the denied state with a button to the system settings, and
        "Reminders scheduled through <horizonEnd>".
        *   The denied state shows while the switch is on and the permission
            reads `denied`, and it takes the place of the date.
        *   Otherwise the date shows only for a saved Protocol whose
            reminders are on, both as saved and in the form, and only while
            the reconciler has a `horizonEnd`. It describes what is stored,
            not the form's unsaved edits. The horizon is one for all
            Protocols (D5, "Its days"), so the date is the same on every
            Protocol screen. (Settled after Phase 5's build.)

##### 57. `apps/mobile/lib/features/protocols/widgets/protocols_day_view.dart` (Modify, Phase 5 part)

*   **Proposed Changes**: The "Reminders are off on this device" banner with
    "Allow" (CUJ 12). It shows when a Protocol has reminders on, the device
    setting is on, and `notificationPermissionStatus()` is `notDetermined`.
    "A Protocol has reminders on" is D5's reading, from
    `anyProtocolRemindersOn()` and `reminderInputs` (file 50), so the banner
    shows even when none of that Protocol's timed doses falls in the
    horizon. (Settled after Phase 5's build.)

##### 58. `apps/mobile/lib/features/protocols/widgets/protocol_reminders_settings.dart` (Create) and `apps/mobile/lib/features/settings/widgets/privacy_settings_screen.dart` (Modify)

*   **Proposed Changes**: A "Supplement reminders" tile under
    `ProtocolsLockSettingsTile`, following its pattern. The tile opens a
    screen with the device setting's switch, the notification permission, and
    "Reminders scheduled through <horizonEnd>".
    *   Opening the screen runs the reconciler, so what it shows is read
        from a fresh run rather than from the last one, which may be from
        before a change in the system settings.
    *   Flipping the device switch saves the setting and then runs the
        reconciler, so turning it off cancels this phone's reminders at
        once. File 49 lists both triggers. (Settled after Phase 5's
        build.)

##### 59. `apps/mobile/lib/l10n/app_en.arb` and generated `app_localizations*.dart` (Modify/Regenerate)

*   **Proposed Changes**: The reminder title and body, the permission strings,
    the banner, and the settings tile and screen.

##### 60. Tests (Create/Modify)

*   `apps/mobile/test/features/protocols/protocol_reminder_plan_test.dart`
    (Create):
    *   grouping (CUJ 1);
    *   dropping filled times (CUJ 2);
    *   off-cycle (CUJ 3);
    *   the mixed reminders-on and reminders-off case;
    *   untimed doses excluded;
    *   a cap that falls mid-day ending the horizon the day before (CUJ 11);
    *   the id formula and its negative range;
    *   daylight-saving-change days.
*   `apps/mobile/test/features/protocols/protocol_reminder_scheduler_test.dart`
    (Create):
    *   the diff against a fake plugin, and no `cancelAll`;
    *   one run at a time under overlapping triggers;
    *   each trigger source;
    *   the device switch off;
    *   lock-independent text and the payload contents;
    *   initialization requests no permission.
*   `apps/mobile/test/features/protocols/protocol_reminder_tap_test.dart`
    (Create): a tap routes through the lock gate to the right date, from a
    cold start and from resume, on both platform paths.
*   `apps/mobile/test/features/training/timer_background_scheduler_test.dart`
    (Modify): `notificationPermissionStatus()` maps every channel value.
*   `apps/mobile/test/features/protocols/protocols_day_view_test.dart`
    (Modify): the CUJ 12 banner.

Building Phase 5 settled the rest of this list:

*   **"Untimed doses excluded"** is not a plan test. Untimed planned doses
    can't reach `desiredReminders`, because `reminderInputs` leaves them
    out, so a plan test of it could never fail. A repository test covers
    it instead, in `protocol_reminder_scheduler_test.dart`: over in-memory
    SQLite, `reminderInputs` carries today's fills, leaves later dates
    unfilled, leaves out untimed doses, and leaves out off-cycle and
    paused days.
*   The iOS tap through the router's new callback (file 52) is covered by
    `protocol_reminder_tap_test.dart`, which also checks that a second
    tap for the Protocol Day on top only selects its date.
*   `apps/mobile/test/features/training/training_screen_test.dart`
    (Modify): its fake `TimerBackgroundScheduler` gains a one-method stub
    for `notificationPermissionStatus()`.
*   **Not tested:** this list has no tests for the Protocol screen's
    Reminders switch (file 56) or the reminder status screen (file 58), so
    Phase 5 added none. Their behaviour is covered only by the manual
    checks in the Verification Plan.

(Settled after Phase 5's build.)

##### 60a. Findings settled after Phase 5's build (Modify)

This entry is lettered so the numbers of every later file stay as they were.
It changes what Phase 5 built, so it lands as its own pull request after
Phase 5's. Nothing in Phase 6 depends on it.

*   **The iOS pending list.** On iOS, `flutter_local_notifications`'
    `pendingNotificationRequests()` reports every pending request the app
    has, including the rest timer's, which `AppDelegate` schedules itself.
    The plugin's native side copies each request's id from its own
    `userInfo["NotificationId"]`, which the rest timer's requests don't
    have. The Dart side then builds a `PendingNotificationRequest` with a
    null id, which its non-nullable `id` refuses. This was found by
    reading the plugin's source (22.3.3); no iOS build has run it. So while
    a rest-timer notification is pending, the read most likely throws, the
    run changes nothing (D5, "One run at a time"), and reminders stay as
    they were until a run after the rest timer's notifications are gone.
    Android isn't affected: the plugin there lists only what it scheduled
    itself.
    *   **The fix:** on iOS, read the pending reminders without the
        plugin's list. `AppDelegate.swift` answers a new
        `pendingProtocolReminders` method on the
        `perennia/timer_background` channel from
        `UNUserNotificationCenter.getPendingNotificationRequests`. It
        returns `{id, payload}` only for requests whose `userInfo` holds
        the plugin's `NotificationId` and a `payload` string, so requests
        the plugin didn't create are skipped.
        `FlutterLocalNotificationsReminderPlatform.pendingNotifications()`
        in `protocol_reminder_scheduler.dart` calls it on iOS, and keeps
        the plugin's `pendingNotificationRequests()` on Android.
    *   **Rejected:** patching or forking the plugin, which would make
        this app carry a modified dependency; and giving the rest timer's
        requests a `NotificationId`, which would make the plugin treat
        them as its own.
*   **iOS 14 presentation options.** `willPresent` in `AppDelegate.swift`
    returns `.banner` and `.list`, which iOS introduced in 14, and the
    Runner target's deployment target is iOS 13.0. Swift reports an API
    newer than the deployment target, used outside an `#available` check,
    as an error, so the target is not expected to compile until this is
    guarded. The guard is `if #available(iOS 14.0, *)`, with `[.alert]` as
    the iOS 13 fallback for both the reminder and the rest timer. The
    deployment target stays 13.0.
*   **Files:**
    *   `apps/mobile/ios/Runner/AppDelegate.swift`: the
        `pendingProtocolReminders` method and the `#available` guard.
    *   `apps/mobile/lib/features/protocols/services/protocol_reminder_scheduler.dart`:
        the iOS read in `FlutterLocalNotificationsReminderPlatform`.
*   **Tests:**
    *   `apps/mobile/test/features/protocols/protocol_reminder_scheduler_test.dart`:
        with the platform's target set to iOS and the timer channel mocked,
        `pendingNotifications()` reads `pendingProtocolReminders` and maps
        its entries. On Android it reads the plugin.
    *   **Manual, on an iPhone:** start a rest timer, then turn a
        Protocol's reminders on; its reminder is scheduled while the rest
        timer's notification is pending. Run the iOS simulator build from
        the Verification Plan.
*   **Not in this entry:** the tests file 60 leaves out for files 56 and
    58.

#### Phase 6: Agent planned-day and status reads

##### 61. `apps/server/src/agent-protocols.ts` (Modify, Phase 6 part)

*   **Proposed Changes**: The two reads, with D6's operation ids, parameters,
    response shapes and errors.
    *   **Doses** are queried with SQL predicates on the user,
        `payload->>'local_date'` within the range, and
        `payload->>'compound_id'` when given. Archived Doses
        (`deleted_at` set) are left out, as matching leaves them out in the
        app. The range compares `local_date` with `collate "C"`, so
        `YYYY-MM-DD` text compares in byte order whatever the database's
        collation. `protocolId` never filters Doses (D6, "With
        `protocolId`, it reads one Protocol's plan"). A Dose's local time
        is its `tookAt` at its frozen offset, or in UTC when it has none
        (D2). (Settled after Phase 6's build.)
    *   **Protocols, Protocol Members and Schedules** are scoped to the
        user. This entry first said all three filter on
        `payload->>'protocol_id'` when given, but only the member payload
        has that key. As built:
        *   Protocols by `id`;
        *   members by `payload->>'protocol_id'`, and by
            `payload->>'compound_id'` when `compoundId` is given;
        *   Schedule Versions by `payload->>'protocol_compound_id'` among
            the ids of the members those filters keep, because a version
            names its member, not its Protocol or Compound.

        With only `compoundId`, every Protocol is read, and one with no
        member of that Compound plans nothing. A member is read only while
        the user holds a row for its Compound (a subquery on `compounds`;
        D6, "Rows the reads can't use"). The three selects run together.
        (Settled after Phase 6's build.)
    *   No expression index is added in v1; the performance budget in file 65
        decides whether one is needed later.
    *   Responses carry statuses and counts only.
    *   **Shared pieces.** `checkAgentProtocolDaysQuery` makes D6's 400
        checks for REST and MCP before any storage read.
        `AGENT_PROTOCOL_DAYS_MAX_RANGE_DAYS` is 366. The `today` bound is
        one helper, which the Protocol batch write's `today_out_of_range`
        check reads too, so both refuse the same `today` with the same
        message. The store's `listProtocolPlannedDays` and
        `listProtocolDayStatuses` parse their own response against the
        response schema, and REST and MCP return it as is, so a large
        range is checked once. (Settled after Phase 6's build.)

##### 62. `apps/server/src/app.ts` and `apps/server/src/index.ts` (Modify, Phase 6 part)

*   **Proposed Changes**: `app.openapi(...)` registrations for both GET
    routes, next to the existing Protocols reads, and their exports. Each
    handler authenticates, runs the shared check (file 61), and returns
    the store's response. (Settled after Phase 6's build.)

##### 63. `apps/server/src/agent-mcp.ts` (Modify)

*   **Proposed Changes**: The MCP tools `agent_list_protocol_planned_days` and
    `agent_list_protocol_day_statuses`, with the same parameters. Each
    tool runs the same check as REST, returns the same
    `agent_protocol_days_invalid_request` body as an error result, and
    calls the same store method. (Settled after Phase 6's build.)

##### 64. Generated contract (Regenerate)

*   **Proposed Changes**: As file 32, for the new routes. The generated
    command-map block of `agent-skills/perennia/references/api-operations.md`
    gains `list-protocol-planned-days` and `list-protocol-day-statuses`.
    (Settled after Phase 6's build.)

##### 65. Tests (Modify)

*   `apps/server/test/agent-protocols.test.mjs`:
    *   range limits and each 400 error;
    *   the required `today`, and its one-day bound;
    *   future dates allowed on planned days and rejected on Day Statuses;
    *   filters, and an empty list for an unknown id;
    *   summary vs `doses` detail;
    *   the reads give the shared core's answer for a stored plan, scoped
        to the user, including a member whose Compound row hasn't synced,
        which plans nothing until it does;
    *   a 366-day request for a user with 2,000 Doses answering within the
        read-latency budget.
        *   **The budget.** This entry assumed an existing read-latency
            budget, but the server had none. It is 250 ms per request,
            end to end through the route against a real Postgres: the
            storage reads, the shared core and the response's schema check.
            Each read is run once to warm up, then three times, and the
            median must be under 250 ms. The constant,
            `AGENT_PROTOCOL_DAYS_READ_BUDGET_MS`, is defined next to its
            test. (Settled after Phase 6's build.)
*   `apps/server/test/agent-mcp-parity.test.mjs`: the new tools match REST.
*   `apps/server/test/observability.test.mjs`: a logged planned-day or Day
    Status read, its query and its response, carries none of the plan
    values. It failed before the four new keys joined the deny-list
    (Non-Functional Requirements). (Settled after Phase 6's build.)
*   **Files no entry listed.** Existing drift and parity tests hold every
    Agent operation to the skill and the MCP tool list, so Phase 6 also
    changed:
    *   `packages/contract/src/agent-skill-reference.ts`: each operation's
        skill command and MCP tool name;
    *   `agent-skills/perennia/scripts/prn-agent.mjs`: the skill's two
        commands, with their method, path and operation id;
    *   `agent-skills/perennia/scripts/prn-code.mjs`: the skill's client
        methods for the two reads;
    *   `apps/server/test/agent-mcp.test.mjs`: the expected list of MCP
        tools;
    *   `apps/server/src/observability.ts`: the four deny-list keys.

    (Settled after Phase 6's build.)

##### 66. `docs/designs/SITEMAP.md` and this spec (Modify)

*   **Proposed Changes**: Status → Current, here and in the spec's
    SITEMAP.md entry, once every entry is built. That needs Phase 6 and
    file 60a, which can merge in either order. Whichever of their pull
    requests merges last sets it; if both merge without setting it, a
    one-line follow-up does. (Settled after Phase 6's build; this entry
    first said "once Phase 6 merges", before file 60a existed.)

### Verification Plan

*   **Build**: `flutter build apk --debug`, plus an iOS simulator build
    (`flutter build ios --simulator --debug`), run by hand at Phase 5,
    because no CI job builds the platforms.
*   **CI gate**: `pnpm ci:local --changed` green on every phase, which runs
    every job whose path filters the phase touches. Expect:
    *   `golden` and `mobile` in Phases 1-5;
    *   `js`, `sync` and `contract` whenever `apps/server` changes (Phases 1,
        2 and 6);
    *   `dependency_hygiene` when a `package.json` or `pubspec.yaml` changes
        (Phases 1 and 5).
*   **Cross-language**: every m36 case passes in both languages. A case that
    passes in one and not the other fails the `golden` job.
*   **Standing scenarios**: kill-and-reopen during "Log all planned" (file
    40); sync convergence with same-day versions (file 34).
*   **Manual, on a device, at Phase 5**:
    *   CUJ 1 at a near-future minute on an iPhone and an Android phone;
    *   with the lock on, the notification text checked on the lock screen;
    *   a rest-timer notification still opens its exercise;
    *   permission denied (CUJ 10) and the second-phone banner (CUJ 12);
    *   a reboot on Android, after which a reminder still fires;
    *   after a timezone change in system settings and a reopen, the next
        reminder moves to the new zone (CUJ 8).
*   **Success**: on a device with `pnpm test-data`'s stack (file 26), each of
    these actions produces its CUJ:
    *   the 09:00 reminder and "Log all planned" (CUJs 1 and 2);
    *   "Skin" on an off-cycle day (CUJ 3);
    *   "Shoulder" passing its end date (CUJ 4);
    *   pausing "Skin" for a week (CUJ 5);
    *   editing TRT to Monday, Wednesday and Friday (CUJ 6);
    *   logging last night's GHK-Cu after midnight (CUJ 7).

--------------------------------------------------------------------------------

<!-- Provenance: Indicates initial structural drafting via EGM. -->

*Drafted with EGM*
