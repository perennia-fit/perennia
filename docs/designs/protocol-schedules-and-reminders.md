# Protocol Schedules and Reminders

*   **Author:** Leonardo Pinheiro
*   **Status:** In Review
*   **Date:** 2026-10-25 (revised 2026-10-26 after Goldfish review)

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
*   **Cancelling reminders on other devices through Sync Nudge.** The server
    already sends Sync Nudges, but the device side that receives them isn't
    wired up. See Alternative O.
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
   │   localDate, timezoneOffsetMinutes        │   │ dayStatuses(planDays, doses,     │
   └──────────────────────────────────────┘   │             today)               │
                                              │ dueUnfilled(dayStatuses, now)    │
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
*   **When a version starts.** The first version of a member applies from the
    Protocol's start date, so a Protocol created today with a start date in the
    past plans those past days. Every later edit applies from the day it is
    made. An edit takes effect that same day (CUJ 6).
*   **Removing a Protocol Member** archives the member row, as today, by the
    app or by an Agent. That archive is the one record of the removal. Days
    before its local archive date still compare against the plan that applied
    then. Days from it read "Not planned" with the reason `removed`.
*   **Re-adding a Compound** creates a new member row, as today. Within a
    Protocol, the core pools the versions of every member row with the same
    Compound, so the history continues.
*   **Archived Protocols** keep their versions. Past days still count an
    archived Protocol and its archived members up to the local date they were
    archived.

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
    `tookAt`. The server already handles IANA zones in two places
    (`localDateInTimezone` in `agent-plan-materialize.ts`, and the formatter
    in `agent-workout-batch-write.ts`). Phase 2 moves that handling into one
    shared helper used by all three, rather than copying it a third time.
    Otherwise it stays null.
*   **Bounds into Effect.** The Effect view's math is unchanged: it works on
    instants, with half-open windows. A new pure function in both languages,
    `effectBoundsFromLocalDates(startLocalDate, endLocalDate?, timezoneOffsetMinutes)`,
    converts a Protocol's local-date bounds into Effect's input. Start becomes
    local midnight of the start date. End becomes local midnight of the day
    after the inclusive end date. The app passes the device's current offset.
    The Agent Effect read gains an optional `timezoneOffsetMinutes` query parameter,
    default 0 (UTC), documented as such.
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
Nothing has shipped. The only data in that shape is developer and generated
test data, and converting it would need permanent compatibility code for users
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
    tables can't be reverted: reverting would write a row in the old shape.
    The revert path refuses it, with a message.
*   **Re-entering.** The developer test-data generator gains the motivating
    stack as three Protocols (Phase 3), so plans for development are one
    command away.

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
    which defaults to the Protocol's start;
*   **times**: a list of `HH:MM` times, or a count of untimed doses;
*   the planned amount, unit and route, as today;
*   or **as needed**, which plans nothing.

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
4.  the Protocol Member was archived on or before the date → `removed`;
5.  otherwise the member's Schedule Version for that date decides:
    *   `as_needed` → `as_needed`;
    *   a rule whose days exclude the date → `not_scheduled_today`;
    *   otherwise → `planned`, with its times or untimed count.

### D5. Reminders are a device-local reconciler over `flutter_local_notifications`

*   **Library:** `flutter_local_notifications`, with `timezone` and
    `flutter_timezone` to schedule wall-clock times in the phone's own zone. The
    plugin is initialized with every permission request turned off, so it never
    asks at startup. The rest timer keeps its existing native channel unchanged.
*   **iOS routing.** `AppDelegate.swift` routes each notification by whether its
    `userInfo["timerId"]` is present. The timer already sets that field, so
    timer notifications keep today's handling. Every other notification is
    forwarded to `super`, in both `didReceive` and `willPresent`, so the plugin
    receives it. A reminder that fires while the app is in the foreground shows
    as a banner and in the notification list.
*   **Android:** inexact delivery (`inexactAllowWhileIdle`), with no
    exact-alarm permission. Delivery is usually within minutes, and up to about
    an hour late under Doze or battery saver. Exact alarms need a user-granted
    permission and a Play policy declaration, so they are a follow-up. The
    plugin's receivers are registered for boot and app updates.
*   **One notification per planned time.** Every planned dose due at that
    minute shares it. A reminder's id is the negative of (1 + the 32-bit FNV-1a
    hash of `"protocolReminder:<date>T<time>"`, masked to 30 bits). Ids are
    deterministic, so re-running the reconciler replaces rather than
    duplicates. They are negative, and the timer's ids are non-negative, so the
    two never collide.
*   **Text is always generic:** title "Supplements", body "Planned for
    9:00 AM". This holds whether or not the lock is on, so turning the lock on
    later can't leave named reminders queued. Android notifications are
    `VISIBILITY_PRIVATE`, and the channel is named "Reminders".
*   **What gets a reminder.** The reconciler's input is a list of
    `{protocolId, compoundId, localDate, localTime, remindersEnabled, filled}`,
    one per timed planned dose, from the Protocol Plan core. A time gets a
    reminder only if at least one unfilled timed planned dose at that time
    belongs to a Protocol with reminders on. Past times never do, and untimed
    planned doses never do.
*   **When it runs.** On app start, on resume, after any change to Protocols,
    Schedules or Doses (debounced 500 ms), and after sync completes. There are
    no background or timezone-change triggers: travel takes effect on the next
    open or resume (CUJ 8).
*   **One run at a time.** A trigger during a run marks the reconciler dirty,
    and exactly one more run follows. The logging path never waits for it.
*   **Cancelling.** It cancels only notifications whose payload kind is
    `protocolReminder`, and never calls `cancelAll`. When the device switch is
    off, or no Protocol has reminders on, it cancels all of its own
    notifications and schedules none.
*   **The scheduling horizon** is `min(14 days, as many days as fit in 48
    pending notifications)`. That leaves 16 of iOS's 64 pending notifications
    for the rest timer, which uses 2 per timer. The Protocol screen shows the
    resulting date next to the Reminders switch (CUJ 11).
*   **Moving a time earlier.** When a same-day edit moves a time to one that
    has already passed, today gets no reminder at that time (CUJ 6). This is
    accepted.
*   **Per device:** a local "Reminders on this device" setting, default on,
    stored in the device-level `settings.json` and never synced. What is
    pending, what fired and what was tapped is never synced and never written
    to the Activity Log.
*   **Permission** is requested when the user first turns reminders on for a
    Protocol, never at onboarding (CUJ 10). On a device where any Protocol has
    reminders on and the device switch is on, but permission was never granted,
    the Protocol Day view shows a banner that requests it (CUJ 12).
*   **Tap:** the payload carries only `{kind: "protocolReminder", localDate}`.
    The app opens through `ProtocolsLockGate`, the widget that shows the PIN or
    biometric prompt when the lock is on, to that date's Protocol Day.

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

Filling by nearest time means a Dose at 20:50 fills a 21:00 slot, not an
unfilled 09:00 one. So the 21:00 reminder doesn't fire after the Dose, and the
morning reads "Not logged", which is what happened. The Protocol tag only
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
        3.  `removed`;
        4.  `outside`.
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

**The Planned list** sits at the top of the Protocol Day view, inside the lock.
It is hidden when the day has nothing planned.

*   **Rows.** Each row is one slot, grouped under its slot's Protocol. It shows
    the Compound, the planned time (or "Any time"), the amount, and one label:
    "Logged" when filled, "Pending" when unfilled today, "Not logged" when
    unfilled on a past day.
*   **Tapping a row** opens the log sheet prefilled with the planned amount and
    route, tagged with the row's Protocol. On today, the time is now. On a past
    day, it is the row's planned time on that date, or 12:00 for an untimed
    row. Both date and time are editable.
*   **"Log all planned"** appears only on today's Protocol Day. It logs every
    due unfilled planned dose: timed ones whose time is at or before now, and
    untimed ones. Each is timed now and tagged with its row's Protocol. All are
    written in one transaction and one Batch (`dueUnfilled` in the core picks
    the rows). Past days have no bulk action.
*   **The log sheet** gains a date field next to its time (CUJ 7). Opened
    outside the Planned list, it defaults to now on today, or 12:00 on a past
    Protocol Day, and the amount still prefills from the last Dose of that
    Compound. It no longer prefills the time from the last Dose; that default
    recorded times that never happened.

**The Consistency view** opens from a Compound's row in the Compound list, or
from a Protocol, where it shows a tab per member. For a date range (default:
the last 30 days, including today), it shows a chart of each Dose's time of day
against the planned times, built with `fl_chart` like the existing Effect
timeline. Below the chart is a day-by-day list of Day Statuses, times and
amounts.

**The Effect view.** Its window input moves to `effectBoundsFromLocalDates`
(D2); its math is unchanged. For a Protocol with a cycle or Pauses, it shows
"Off-cycle and paused days are counted as during."

**The "N doses" helper** (`endDateForDoseCount`, Dart only):

*   **What it returns:** the local date of the Nth planned dose of one member,
    counted from the Protocol's start. It counts doses, not days: a rule of
    08:00 and 20:00 reaches 20 doses on day 10. It skips off-cycle and paused
    days, and uses the member's current rule.
*   **Limits:** N is 1 to 1000. For an `as_needed` rule it returns
    "unavailable".
*   **Why Dart only:** no Agent operation uses it.

**Contract changes for the Agent surface:**

*   **Naming.** Agent fields are camelCase, like the rest of the Agent API:
    `startLocalDate`, `endLocalDate`, `period`, `remindersEnabled`,
    `effectiveFrom`, `rule`, `timezoneOffsetMinutes`. Snake_case stays only in Drift
    columns and sync payloads.
*   **Same release as the app.**
    *   Protocol and Schedule reads and writes carry the new fields, validated
        by the shared two-tier module (D7).
    *   `frequency` is removed from Agent Schedule writes; a write that
        includes it is rejected.
    *   Agent Schedule writes carry `today`, the user's local date, as the Day
        Status read does. The server assigns `effectiveFrom` exactly as the
        app does: the Protocol's start for a member's first version, otherwise
        `today`. A write can't set `effectiveFrom` itself, can't reuse an
        existing version id, and can't archive a version, so versions are
        insert-only for Agents as they are for the app. Removing a Compound
        from a Protocol is the existing member archive.
    *   Dose writes gain an optional `timezoneOffsetMinutes` (D2).
    *   The Effect read gains an optional `timezoneOffsetMinutes` (D2).
*   **Later stage.** Two new reads, mirrored as MCP tools:
    *   `listAgentProtocolPlannedDays`: `GET /agent/protocols/planned-days`, MCP
        tool `agent_list_protocol_planned_days`.
        *   Parameters: `fromLocalDate` and `toLocalDate` (inclusive, at most
            366 days apart; future dates allowed), plus optional `compoundId`
            and `protocolId`.
        *   Returns the `PlanDay` records of the core API.
    *   `listAgentProtocolDayStatuses`: `GET /agent/protocols/day-statuses`, MCP
        tool `agent_list_protocol_day_statuses`.
        *   Parameters: the same as the first, plus a required `today` and
            `detail=summary|doses`, default `summary`. `toLocalDate` must not
            be after `today`.
        *   With `summary`, returns
            `{compoundId, localDate, status, notPlannedReason?, plannedCount, loggedCount, extraCount}`.
            With `doses`, it also returns `fills`.
    *   Errors: 400 for a range over 366 days, for `fromLocalDate` after
        `toLocalDate`, and for `toLocalDate` after `today`. Unknown ids return
        an empty list.
*   **The contract diff.** It shows these field and route changes in
    `packages/contract/openapi.json` and the generated clients. Responses
    carry statuses and counts only, with no ratio or streak field.

### D7. Validation

Plan values join the shared two-tier validation module. Dart adds
`apps/mobile/lib/domain/protocols/protocol_plan_validation.dart`, following the
existing plan-validation precedent
(`apps/mobile/lib/domain/training/plan_validation.dart`). TypeScript extends
`apps/server/src/agent-validation.ts`, where that precedent's twin also lives.
Results use the Dose validator's issue shape (`DoseValidationIssue` in Dart,
`AgentDoseValidationIssueSchema` in TypeScript): errors and warnings whose
`rule` field is the stable id of the check below. The same golden vectors run
in Dart and TypeScript.

| Check id | Field | Condition | Tier |
| :------- | :---- | :-------- | :--- |
| `times_format` | rule.times | each time is `HH:MM`, 00:00-23:59 | reject |
| `times_count` | rule.times | 1 to 12 times | reject |
| `times_distinct` | rule.times | no duplicates (stored sorted) | reject |
| `untimed_count` | rule.count | 1 to 12 | reject |
| `weekdays_valid` | rule.days.weekdays | non-empty, each 1-7, no duplicates | reject |
| `every_n_range` | rule.days.n | 2 to 365 | reject |
| `anchor_date` | rule.days.anchor, period.cycle.anchor | a valid date | reject |
| `amount_required` | amount | present for `timed` and `untimed`, and valid per the Dose validator | reject |
| `cycle_lengths` | period.cycle | on and off lengths each 1 to 3650 days | reject |
| `bounds_order` | endLocalDate | not before startLocalDate (replaces `validateProtocolWindow`) | reject |
| `pause_order` | period.pauses | each has from ≤ to | reject |
| `pause_bounds` | period.pauses | within the Protocol's bounds | reject |
| `pause_overlap` | period.pauses | no two overlap | reject |
| `times_many` | rule.times | more than 6 a day, which is more often a typo than a plan | warn |

Two checks sit outside the shared module, because only one side has what they
need. The "N doses" helper rejects N outside 1-1000; it is Dart only. Agent
Schedule writes must carry a valid `today`; that is the server's write path
(D6).

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
    shape are developer and generated data. Clearing them once costs a
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
        that hold every new field, so no keys are added. A test (file 25)
        proves a logged Protocol or Schedule write carries none of the plan
        values.
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
    (Phase 4) pins the worst case of these.
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

These fix problems that exist independently of this feature. Each lands as its
own pull request.

| # | Fix | Done when | Status |
| :- | :-- | :-------- | :----- |
| P1 | Agent Schedule writes are validated against the app's registries. An independent fix for a live crash, not a prerequisite: today a frequency such as "daily" makes the app throw when it reads the Schedule. Phase 2 retires `frequency` and clears these rows, so P1 matters only until Phase 2 lands. | The Agent API rejects a frequency, unit or route outside the app's registries, or a missing amount; golden vectors cover it in both languages. | Pending |
| P2 | Sync pull skips entity types it doesn't recognize, and sets aside malformed rows. | A pull with an unknown entity type, or a malformed known row, skips it, saves the cursor and continues. | Done ([perennia-fit/perennia#34](https://github.com/perennia-fit/perennia/pull/34), [#38](https://github.com/perennia-fit/perennia/pull/38)) |
| P3 | The Effect window agrees across languages. | `m29-effect-window.json` runs in both suites, and both pass. | Done ([perennia-fit/perennia#36](https://github.com/perennia-fit/perennia/pull/36)) |
| P4 | CI runs every golden vector in both languages. | A change to `packages/golden-vectors/**` runs both suites. | Done ([perennia-fit/perennia#37](https://github.com/perennia-fit/perennia/pull/37), [#39](https://github.com/perennia-fit/perennia/pull/39)) |
| P5 | The docs describe how Protocols data syncs. | [ARCHITECTURE.md](../../ARCHITECTURE.md) no longer says the Protocols payload is opaque to the server. The server does read it, which is what gives the user's Agent full access. | Pending |

## Detailed Implementation Plan

Work lands in six phases, each its own pull request, after P5. Each phase
leaves the app buildable, the CI gate (`pnpm ci:local`) green, and the app
usable. File paths start from the repository root.

### Data shapes (fixed by this spec)

**`protocols` row** (Drift and sync payload):

| Field | Type | Meaning |
| :---- | :--- | :------ |
| `start_local_date` | `YYYY-MM-DD` | Replaces the `start_date` instant |
| `end_local_date` | `YYYY-MM-DD`, nullable | Inclusive; replaces the `end_date` instant. Null = ongoing |
| `period` | JSON, nullable | `{"v":1,"cycle":null \| {"on_days":int,"off_days":int,"anchor":"YYYY-MM-DD"},"pauses":[{"from":"YYYY-MM-DD","to":"YYYY-MM-DD"}]}`. Null = no cycle, no Pauses |
| `reminders_enabled` | bool, default false | Synced plan data: "remind me about this Protocol" |

**`schedules` row = one Schedule Version:**

| Field | Type | Meaning |
| :---- | :--- | :------ |
| `effective_from` | `YYYY-MM-DD` | The local date this version applies from (D1) |
| `rule` | JSON | The Schedule Rule; replaces `frequency`, which is dropped |
| `dose_amount_value`, `dose_amount_entered`, `dose_unit`, `route` | as today, now nullable | Required by D7 for `timed` and `untimed` rules; null for `as_needed` |

`rule` JSON, version 1:

```text
{"v":1,"kind":"timed",   "days":DAYS,"times":["HH:MM", ...]}   1..12 distinct times, stored sorted
{"v":1,"kind":"untimed", "days":DAYS,"count":int}              1..12
{"v":1,"kind":"as_needed"}
DAYS = {"kind":"daily"}
     | {"kind":"weekdays","weekdays":[1..7, ...]}              ISO 8601, 1 = Monday
     | {"kind":"every_n_days","n":2..365,"anchor":"YYYY-MM-DD"}
```

**`doses` row:** adds `timezone_offset_minutes` (int, nullable; null on Doses
logged before this change, and on Agent writes that give neither an offset nor
an IANA zone).

**Version rules** (D1): every edit inserts a row; a member's first version
applies from the Protocol's start date, and later edits from today; removing a
Protocol Member archives the member row; versions are never deleted.

### Shared core API (pure; Dart and TypeScript mirror each other)

In Dart, `LocalDate` is the existing `ProtocolDayDate`
(`apps/mobile/lib/domain/protocols/protocols.dart`). In TypeScript it is a
`YYYY-MM-DD` string.

```text
planDays(protocols: PlanProtocol[], from: LocalDate, to: LocalDate) -> PlanDay[]
  PlanProtocol = {protocolId, startLocalDate, endLocalDate?, period?,
                  archivedOn?: LocalDate,
                  members: [{compoundId, archivedOn?: LocalDate,
                             versions: [{id, effectiveFrom, rule, amount?, unit?, route?}]}]}
                 (members with the same compoundId are pooled)
  PlanDay      = {protocolId, compoundId, localDate,
                  state: "planned" | "not_scheduled_today" | "as_needed" |
                         "removed" | "outside" | "paused" | "off_cycle",
                  planned: [{localTime: "HH:MM" | null, amount?, unit?, route?}]}

dayStatuses(planDays: PlanDay[], doses: PlanDose[], today: LocalDate) -> DayStatus[]
  PlanDose  = {doseId, compoundId, localDate, localTime: "HH:MM", sequence: int}
  DayStatus = {compoundId, localDate,
               status: "not_planned" | "paused" | "off_cycle" | "pending" |
                       "logged" | "partly_logged" | "not_logged",
               notPlannedReason?: "not_scheduled_today" | "as_needed" |
                                  "removed" | "outside",
               plannedCount, loggedCount, extraCount,
               fills: [{slot: int, protocolId, plannedLocalTime: "HH:MM" | null,
                        doseId: string | null}]}
  Dates after `today` are not returned. Matching and status order: D6.

dueUnfilled(dayStatuses: DayStatus[], nowLocalTime: "HH:MM") -> [{compoundId, slot, protocolId}]
effectBoundsFromLocalDates(startLocalDate, endLocalDate?, timezoneOffsetMinutes)
  -> {startDate: instant, endDate: instant | null}                  (D2)
endDateForDoseCount(startLocalDate, rule, period?, count) -> LocalDate | unavailable
  (Dart only; D6)
```

Callers convert archive timestamps to local dates before calling. No function
parses an instant or a timezone, except `effectBoundsFromLocalDates`, which
applies the offset it is given.

### Target Files to Create/Modify

#### Phase 1: the shared core and its vectors (no user-visible change)

Each golden-vector file carries one top-level `domain` and is registered with
both ownership guards: the Dart map in
`apps/mobile/test/domain/golden_vector_ownership_test.dart`, and, for a domain
another TypeScript runner owns, `DOMAINS_OWNED_ELSEWHERE` in
`apps/server/test/agent-validation.golden.test.mjs`.

##### 1. `packages/golden-vectors/vectors/m36-protocol-plan.json` (Create)

*   **Type / Scope**: Golden vectors, `domain: "protocol-plan"`.
*   **Proposed Changes**: Each case names the function it exercises
    (`function`: `rule_codec`, `period_codec`, `plan_days`, `day_statuses`,
    `due_unfilled` or `effect_bounds`).

    **Required cases:**
    *   every CUJ in this spec, with its dates;
    *   **matching:** the 20:50-fills-21:00 case; an early and a late Dose; two
        morning Doses; mixed timed and untimed slots; an extra Dose;
    *   **plan structure:** an every-N-days anchor before the range; a cycle
        anchor before the start; a backdated Protocol start; overlapping
        Protocols for one Compound;
    *   **versions and members:** two versions on the same date (the id
        tie-break); a removed and re-added member; an archived Protocol's past
        days;
    *   **statuses:** each `notPlannedReason`.

    Top-level `schemaVersion: 1`.

##### 1a. `packages/golden-vectors/vectors/m36-protocol-plan-validation.json` (Create)

*   **Type / Scope**: Golden vectors, `domain: "protocol-plan-validation"`.
*   **Proposed Changes**: Every D7 check in the table, passing and failing.
    Top-level `schemaVersion: 1`.

##### 2. `packages/golden-vectors/vectors/m36-protocol-plan.schema.json` and `m36-protocol-plan-validation.schema.json` (Create)

*   **Type / Scope**: JSON Schema.
*   **Proposed Changes**: One schema for each of files 1 and 1a, as
    `m34-routine-up-next.schema.json` does for its file. Each `schemaVersion`
    constant matches its runners' constants.

##### 3. `packages/golden-vectors/vectors/README.md` (Modify)

*   **Proposed Changes**: A section for m36 stating the version rule (the file's
    constant and its runners' constants move together), and that cases contain
    no timezones: offsets appear only in `effect_bounds` cases.

##### 4. `apps/mobile/lib/domain/protocols/protocol_plan.dart` (Create)

*   **Type / Scope**: Dart pure domain.
*   **Proposed Changes**:
    *   Types and JSON codecs for Schedule Rule, Protocol Period, Pause,
        Schedule Version, `PlanProtocol`, `PlanDay`, `PlanDose` and
        `DayStatus`.
    *   The codecs reject unknown `kind`s and any `v` other than 1.
    *   Uses `ProtocolDayDate` for dates.

##### 5. `apps/mobile/lib/domain/protocols/protocol_plan_days.dart` (Create)

*   **Proposed Changes**: `planDays`, `dayStatuses`, `dueUnfilled` and
    `endDateForDoseCount`, following D4 and D6. It does no I/O.

##### 6. `apps/mobile/lib/domain/protocols/protocol_plan_validation.dart` (Create)

*   **Proposed Changes**: `validateScheduleRule` and `validateProtocolPeriod`,
    implementing the D7 table and returning the Dose validator's issue shape.
    It follows `apps/mobile/lib/domain/training/plan_validation.dart`, the
    existing precedent for plan validation with a TypeScript twin in
    `agent-validation.ts`.

##### 7. `apps/mobile/lib/domain/effect/effect.dart` (Modify)

*   **Proposed Changes**: Adds `effectBoundsFromLocalDates` (D2). The Effect
    math is unchanged.

##### 8. `apps/mobile/test/domain/protocol_plan_golden_test.dart` and `apps/mobile/test/domain/protocol_plan_validation_test.dart` (Create)

*   **Proposed Changes**: The first runs every case in file 1 against files 4,
    5 and 7. The second runs every case in file 1a against file 6. Each asserts
    its schema-version constant equals its file's.

##### 8a. `apps/mobile/test/domain/golden_vector_ownership_test.dart` (Modify)

*   **Proposed Changes**: Map `protocol-plan` to
    `test/domain/protocol_plan_golden_test.dart`, and
    `protocol-plan-validation` to `test/domain/protocol_plan_validation_test.dart`.

##### 9. `apps/mobile/test/domain/protocol_plan_dose_count_test.dart` (Create)

*   **Proposed Changes**: Dart-only tests for `endDateForDoseCount`: CUJ 4, a
    two-time rule, cycles, Pauses, `as_needed`, and N outside 1-1000.

##### 10. `apps/server/src/protocol-plan.ts` (Create)

*   **Type / Scope**: TypeScript twin of files 4 and 5, except
    `endDateForDoseCount`.
*   **Proposed Changes**: The same functions and JSON, with no database access.

##### 11. `apps/server/src/agent-validation.ts` (Modify)

*   **Proposed Changes**: Adds the D7 checks next to `validateAgentDose`, with
    the same issue shape.

##### 12. `apps/server/src/agent-protocols.ts` (Modify, Phase 1 part)

*   **Proposed Changes**: Adds `effectBoundsFromLocalDates` next to
    `deriveEffectWindow`. Nothing calls it yet.

##### 13. `apps/server/test/protocol-plan.golden.test.mjs` (Create) and `apps/server/test/agent-validation.golden.test.mjs` (Modify)

*   **Proposed Changes**:
    *   The new runner runs every case in file 1 against files 10 and 12.
    *   `agent-validation.golden.test.mjs` runs file 1a's cases against file
        11, and adds `protocol-plan` to `DOMAINS_OWNED_ELSEWHERE`, owned by the
        new runner.

##### 14. `apps/server/package.json`, `.github/workflows/ci.yml`, `tools/ci-local.mjs` (Modify)

*   **Proposed Changes**:
    *   Add `test/protocol-plan.golden.test.mjs` to the `test:golden-vectors`
        script.
    *   Add `apps/server/src/protocol-plan.ts` and that test file to the
        `golden_vectors` path filters, in `ci.yml` and `ci-local.mjs` in the
        same commit.

#### Phase 2: storage, sync, the plan editor, Effect input and the Agent plan shape

##### 15. `apps/mobile/lib/data/local/app_database.dart` (Modify)

*   **Type / Scope**: Drift schema, the current version + 1 (60 → 61 as of
    this revision).
*   **Proposed Changes**:
    *   Delete every row of `protocol_target_outcomes`, `schedules`,
        `protocol_compounds` and `protocols`, in that order (D3).
    *   Rebuild `protocols` and `schedules` with Drift's `TableMigration` to
        the shapes above. `start_date`, `end_date` and `frequency` are
        dropped.
    *   Add `doses.timezone_offset_minutes`.
    *   Add an index on `schedules (protocol_compound_id, effective_from)`.
    *   Mark nothing as pending sync. After the rebuild,
        `PRAGMA foreign_key_check` must return no rows.

##### 16. `apps/mobile/lib/data/local/app_database.g.dart` (Regenerate)

*   **Proposed Changes**: `build_runner` output for file 15.

##### 17. `apps/mobile/lib/domain/protocols/protocols.dart` and `apps/mobile/lib/domain/protocols/protocol_validation.dart` (Modify)

*   **Proposed Changes**:
    *   `ScheduleFrequency`, `scheduleFrequencyLabel` and
        `scheduleFrequencyFromName` are removed.
    *   `ProtocolDraft`, `ProtocolSummaryRecord` and `ProtocolRecord` replace
        their `DateTime` bounds with `startLocalDate` and `endLocalDate`, and
        gain `period` and `remindersEnabled`.
    *   The Schedule read model exposes the version that applies today, with
        its `rule` and `effectiveFrom`.
    *   `DoseRecord` gains `timezoneOffsetMinutes` and a derived `localTime`.
    *   `validateProtocolWindow` is removed from `protocol_validation.dart`;
        its callers use D7's `bounds_order` check.
    *   Doc comments that cite unpublished section numbers are rewritten to
        state the rule they rely on.

##### 18. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

*   **Type / Scope**: `ProtocolsRepository`. Edits stay inside the existing
    Protocols methods; new reads go in file 20.
*   **Proposed Changes**:
    *   **Logging:**
        *   `logDose` writes `timezoneOffsetMinutes` from
            `tookAt.timeZoneOffset`.
        *   New `logDoses(List<DoseSnapshotDraft>)` runs one transaction and
            one Batch over the existing private `_logDose`.
    *   **Schedules:** the Schedule reconcile path inserts a version row on
        every edit, and no longer updates the active Schedule in place.
        Removing a Protocol Member archives the member row only.
    *   **Protocols:**
        *   Create and edit write local-date bounds, `period` and
            `reminders_enabled`, validated by file 6.
        *   The Effect call site (~7577) passes
            `effectBoundsFromLocalDates(…, device offset)` into
            `effectWindowForProtocol`.
    *   **Sync images:** the image writers and readers for protocols,
        schedules and doses carry the new fields. An incoming row without
        them is treated as malformed, and the existing quarantine of malformed
        rows sets it aside.

##### 18a. `apps/mobile/lib/features/activity/repositories/activity_feed_repository.dart` and `apps/server/src/agent-activity.ts` (Modify)

*   **Proposed Changes**: Reverting an Activity Log entry for `protocols`,
    `protocol_compounds`, `schedules` or `protocol_target_outcomes` is refused
    when its before-image lacks the new shape (no `start_local_date` on a
    Protocol, no `rule` on a Schedule). The refusal says the entry predates
    the change (D3).

##### 19. `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart` (Modify, Phase 2 part)

*   **Proposed Changes**:
    *   **Bounds:** date-only pickers bound to the local dates. The start-date
        formatting (~210) reads `startLocalDate`.
    *   **A "Period" section:**
        *   an "Until" switch with an end date;
        *   an "N doses" helper that asks which Protocol Member to count and
            fills the end date from `endDateForDoseCount`;
        *   a "Cycle" switch with on days, off days and anchor date;
        *   a Pauses list with add, edit and remove.
    *   **Each Protocol Member's Schedule editor:** replaces the frequency
        picker with days (daily, weekday chips, every N days) and times (a list
        of time pickers), or an untimed count, or "As needed".
    *   **Validation:** rejects and warnings from file 6 show inline, as Dose
        validation does.
    *   **Strings:** the editor's strings go into
        `apps/mobile/lib/l10n/app_en.arb`, and the generated
        `app_localizations*.dart` is regenerated.

##### 20. `apps/mobile/lib/data/repositories/protocol_plan_repository.dart` (Create)

*   **Type / Scope**: Repository reads, laid out like
    `apps/mobile/lib/data/repositories/routine_up_next_repository.dart`.
*   **Proposed Changes**: Streams that build `PlanProtocol`s and `PlanDose`s
    from Drift and run the core:
    *   `watchPlannedDay(localDate)`;
    *   `watchConsistency(compoundId, from, to)`;
    *   `reminderInputs(from, to)` for the reminder reconciler.

    Archived Protocols and members are included, with `archivedOn` set to the
    local date of `deleted_at` in the device zone.

##### 21. `apps/mobile/lib/features/sync/repositories/sync_repository.dart` (Modify)

*   **Proposed Changes**: `syncProtocolVersion` 1 → 2.

##### 22. `apps/mobile/lib/data/repositories/portable_archive_repository.dart` (Modify)

*   **Proposed Changes**: `archiveFormatVersion` stays 1; the manifest's
    `schemaVersion` tells old shapes apart, as it does today. An archive from
    schema 60 or earlier imports its Compounds and Doses, and skips its
    Protocols, Protocol Members, Schedules and target outcomes (D3).
    Merge-only behavior is unchanged.

##### 23. `apps/server/src/sync.ts` (Modify)

*   **Proposed Changes**: `SYNC_PROTOCOL_VERSION` 1 → 2.

##### 23a. `apps/server/drizzle/<next>_clear_protocol_plans.sql` (Create)

*   **Type / Scope**: A custom migration, created with
    `drizzle-kit generate --custom --name=clear_protocol_plans` so its journal
    entry is generated too. It is numbered after the latest migration (0032 as
    of this revision).
*   **Proposed Changes**: Deletes every row of `protocol_target_outcomes`,
    `schedules`, `protocol_compounds` and `protocols`, in that order (D3).

##### 24. `apps/server/src/agent-protocols.ts` (Modify, Phase 2 part)

*   **Proposed Changes**:
    *   **Protocol and Schedule fields** follow D6's contract changes:
        camelCase; `frequency` rejected; Schedule writes carry `today` and
        the server assigns `effectiveFrom`; versions are insert-only.
    *   **Validation:** every write runs file 11's checks.
    *   **Reads** return the new shape.
    *   **Doses:**
        *   writes accept an optional `timezoneOffsetMinutes`, or derive it
            from an IANA `timezone` and `tookAt` through file 24a;
        *   the `timezone` field description says it is a display label;
        *   reads return `timezoneOffsetMinutes`.
    *   **The Effect read** gains an optional `timezoneOffsetMinutes` (default
        0). It builds its Protocol window source with
        `effectBoundsFromLocalDates` instead of parsing `start_date` (~1634-1680,
        ~2040-2054).

##### 24a. `apps/server/src/timezone.ts` (Create), `apps/server/src/agent-plan-materialize.ts` and `apps/server/src/agent-workout-batch-write.ts` (Modify)

*   **Proposed Changes**: Moves `localDateInTimezone` and the IANA-zone
    formatter into one module, adds `offsetMinutesInTimezone(instant, zone)`
    built on the same formatter, and has both existing callers import it. No
    behavior change for them.

##### 25. `apps/server/test/observability.test.mjs` (Modify)

*   **Proposed Changes**: A test that scrubbing a logged Agent Protocol write
    and a logged Schedule write leaves none of their plan values (`period`,
    `rule`, the local dates). The deny-list already covers their parent keys,
    so `apps/server/src/observability.ts` doesn't change unless this test
    fails.

##### 26. Generated contract (Regenerate)

*   **Files**:
    *   `packages/contract/openapi.json`
    *   `packages/contract/src/agent-client.ts`
    *   `apps/mobile/lib/api/perennia_api_client.dart`
    *   `agent-skills/perennia/references/api-operations.md`
*   **Proposed Changes**: `pnpm --filter @perennia/contract generate` output,
    committed. The example that writes `"frequency": "daily"` is regenerated
    with a `rule`.

##### 27. `CONTEXT.md` (Modify)

*   **Proposed Changes**: Rewrite **Schedule**, and add every term marked
    "yes" in [New and changed terms](#new-and-changed-terms). Planned dose and
    Day Status are marked "derived, never stored".

##### 28. Tests (Create/Modify)

*   `apps/mobile/test/data/protocol_plan_migration_test.dart` (Create):
    *   schema 60 → 61 on a seeded database;
    *   Compounds and Doses survive unchanged, and the four plan tables are
        empty;
    *   no row is marked pending sync;
    *   the foreign key check is clean.
*   `apps/mobile/test/features/protocols/protocols_repository_test.dart`
    (Modify):
    *   every edit inserts a version, including two edits on the same day;
    *   the first version's date equals the Protocol's start;
    *   removing a Protocol Member archives it, and days after read `removed`;
    *   re-adding the member continues its history;
    *   `logDoses` is all-or-nothing;
    *   `timezoneOffsetMinutes` is written;
    *   an incoming row in the old shape is quarantined;
    *   the Effect window comes from local-date bounds.
*   `apps/mobile/test/features/protocols/protocol_screen_test.dart` (Modify):
    the period, Pause and rule editors; the "N doses" helper; validation
    messages; ≥ 48 dp targets.
*   `apps/mobile/test/data/portable_archive_repository_test.dart` (Modify): a
    schema-60 archive imports its Compounds and Doses and skips its plan rows.
*   `apps/mobile/test/features/activity/activity_feed_repository_test.dart` and
    `apps/server/test/agent-activity.test.mjs` (Modify): reverting a
    pre-change plan entry is refused.
*   `apps/server/test/agent-protocols.test.mjs` (Modify):
    *   D7 rejects and warnings;
    *   `frequency` rejected;
    *   `effectiveFrom` assigned from `today`, and a supplied `effectiveFrom`,
        a reused version id or a version archive rejected;
    *   Dose offset derivation;
    *   the Effect read with and without `timezoneOffsetMinutes`.
*   `apps/server/test/sync-convergence.test.mjs` (Modify): two devices write
    same-day versions offline and converge to the larger id, and a version-1
    request is rejected.

#### Phase 3: the Planned list

##### 29. `apps/mobile/tool/test_data/test_data_generator.dart` and `apps/mobile/test/tool/test_data_generator_test.dart` (Modify)

*   **Proposed Changes**: The generator adds the motivating stack as three
    Protocols, written through the app's repositories like the rest of its
    data:
    *   "Daily": TRT and AgeMate at 09:00, creatine at 17:00;
    *   "Skin": GHK-Cu at 21:00, on a 60/30 cycle anchored 60 days back;
    *   "Shoulder": BPC-157 at 21:00, ending in 10 days.

    It also adds four weeks of Doses with some days left unlogged. Its test
    asserts the three Protocols and the Doses exist.

##### 30. `apps/mobile/lib/features/protocols/widgets/protocols_day_view.dart` (Modify)

*   **Proposed Changes**: The Planned list above the logged Doses, driven by
    `watchPlannedDay`. Its rows, labels, "Log all planned" and the log sheet's
    date field and prefill rules are as in D6.

##### 31. `apps/mobile/lib/features/protocols/controllers/protocols_day_controller.dart` (Modify)

*   **Proposed Changes**: Exposes the planned-day stream. "Log all planned"
    takes the rows from `dueUnfilled` and calls `ProtocolsRepository.logDoses`
    once. Each Dose is tagged with its row's Protocol and timed now.

##### 32. `apps/mobile/lib/features/protocols/widgets/effect_screen.dart` (Modify)

*   **Proposed Changes**: For a Protocol with a cycle or Pauses, shows
    "Off-cycle and paused days are counted as during."

##### 33. `apps/mobile/lib/l10n/app_en.arb` and generated `app_localizations*.dart` (Modify/Regenerate)

*   **Proposed Changes**: Strings for:
    *   the Planned list's three row labels;
    *   the seven Day Status labels and four not-planned reasons;
    *   the Effect notice.

    No string uses a word D6 bans.

##### 34. Tests (Create/Modify)

*   `apps/mobile/test/features/protocols/protocols_day_view_test.dart`
    (Modify):
    *   the Planned list's labels;
    *   "Log all planned" leaving a later row Pending (CUJ 1);
    *   no bulk action on past days;
    *   two-tap logging from a row;
    *   the date field;
    *   labels present alongside color;
    *   contrast in both themes.
*   `apps/mobile/test/features/protocols/log_dose_sheet_test.dart` (Modify):
    the prefill rules, today and past days.
*   `apps/mobile/test/features/protocols/protocol_plan_reopen_test.dart`
    (Create): the app is killed during "Log all planned". After reopening, the
    Batch is either fully applied or absent, and the Planned list matches.
*   `apps/mobile/test/features/protocols/effect_screen_test.dart` (Modify): the
    notice shows only for a cycle or Pauses.

#### Phase 4: the Consistency view

##### 35. `apps/mobile/lib/features/protocols/widgets/consistency_screen.dart` (Create)

*   **Proposed Changes**:
    *   Opens for one Compound, or for a Protocol with a tab per member.
    *   A range picker: the last 30 days (including today) by default; 7, 90
        or 365 days; or a custom range up to 366 days.
    *   The chart (file 36) above a day list. Each day shows its Day Status
        label and reason, the logged times and amounts, and the planned times
        and amounts, as D6 describes.
    *   It shows the existing "For personal tracking; not medical advice."
        notice.

##### 36. `apps/mobile/lib/features/protocols/widgets/consistency_chart.dart` and `apps/mobile/lib/features/protocols/models/consistency_chart_data.dart` (Create)

*   **Proposed Changes**: An `fl_chart` scatter. X is the date and Y is the
    time of day. Each logged Dose is a point, and each planned time is a
    horizontal segment over the days it applies. Off-cycle and paused days are
    shaded and labelled. The model is pure and tested, following
    `effect_timeline_chart_data.dart`.

##### 37. `apps/mobile/lib/features/protocols/controllers/consistency_controller.dart` (Create)

*   **Proposed Changes**: The range state and the `watchConsistency` stream.

##### 38. Entry points (Modify)

*   **Files**:
    *   `apps/mobile/lib/features/protocols/widgets/compound_list_screen.dart`
    *   `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart`
*   **Proposed Changes**: Each Compound row in the Compound list gets a
    "Consistency" icon button (≥ 48 dp). The Protocol screen gets a
    "Consistency" button. Both open file 35.

##### 39. Tests (Create)

*   `apps/mobile/test/features/protocols/consistency_screen_test.dart`: labels
    and reasons, the range picker, both entry points, and none of the words D6
    bans.
*   `apps/mobile/test/features/protocols/consistency_chart_data_test.dart`:
    planned segments across a version change (CUJ 6), and shading (CUJ 3 and
    5).
*   `apps/mobile/test/performance/protocol_plan_performance_test.dart`: 366
    days for one Compound in 3 Protocols with 5 versions and 800 Doses,
    through `planDays` and `dayStatuses`. It must finish in under 50 ms in a
    debug test run.

#### Phase 5: reminders

##### 40. `apps/mobile/pubspec.yaml` and `pubspec.lock` (Modify)

*   **Proposed Changes**: Add `flutter_local_notifications`, `timezone` and
    `flutter_timezone`, at their current stable versions at implementation
    time.

##### 41. `apps/mobile/lib/features/protocols/services/protocol_reminder_plan.dart` (Create)

*   **Type / Scope**: Pure Dart.
*   **Proposed Changes**:
    `desiredReminders(inputs, now, horizonDays: 14, cap: 48) -> [ReminderSpec{id, localDate, localTime}]`.
    It applies D5:
    *   eligibility: reminders-on Protocols, unfilled timed planned doses,
        future times only;
    *   one reminder per (date, time);
    *   the earliest 48;
    *   the negative id scheme.

    It also returns the horizon's end date.

##### 42. `apps/mobile/lib/features/protocols/services/protocol_reminder_scheduler.dart` (Create)

*   **Proposed Changes**: The reminder reconciler, wrapping the plugin.
    *   **On start,** it initializes the plugin with permission requests off
        and the timezone database, with the local zone from `flutter_timezone`.
    *   **`reconcile()`** diffs `desiredReminders` against the pending
        notifications whose payload kind is `protocolReminder`, then cancels
        and schedules. It never calls `cancelAll`.
    *   **Notifications** use `zonedSchedule` with `inexactAllowWhileIdle`,
        title "Supplements", body "Planned for <localized time>", channel
        "Reminders", and `VISIBILITY_PRIVATE`.
    *   **It runs** on the D5 triggers, one run at a time with a dirty flag.
        When the device switch is off or no Protocol has reminders on, it
        cancels its own notifications and schedules none.
    *   **It exposes** the permission state and the horizon end date for the
        UI.

##### 43. `apps/mobile/lib/app.dart` (Modify)

*   **Proposed Changes**: Start the reminder reconciler after the first frame,
    next to `TimerNotificationRouter.start()`. Route a `protocolReminder` tap,
    including one buffered from a cold start, through `ProtocolsLockGate` to
    the Protocol Day for the payload's date.

##### 44. `apps/mobile/ios/Runner/AppDelegate.swift` (Modify)

*   **Proposed Changes**: In `didReceive` and `willPresent`, a notification
    whose `userInfo["timerId"]` is present keeps today's timer handling.
    Every other notification goes to `super`, so the plugin receives it, and
    reminders in the foreground present as banner and list. The plugin is
    registered as its documentation requires. The timer's own notifications
    are unchanged.

##### 45. `apps/mobile/android/app/src/main/AndroidManifest.xml` and `apps/mobile/android/app/build.gradle.kts` (Modify)

*   **Proposed Changes**:
    *   Register the plugin's `ScheduledNotificationReceiver` and
        `ScheduledNotificationBootReceiver`, the latter for `BOOT_COMPLETED`
        and `MY_PACKAGE_REPLACED`.
    *   Add the `RECEIVE_BOOT_COMPLETED` permission. No exact-alarm
        permission.
    *   Enable core library desugaring, as the plugin requires.

##### 46. `apps/mobile/lib/features/settings/repositories/settings_repository.dart` (Modify)

*   **Proposed Changes**: Device-level `protocolRemindersOnThisDevice`, default
    true, in `settings.json`. Never synced.

##### 47. `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart` (Modify, Phase 5 part)

*   **Proposed Changes**: The Reminders switch, bound to `reminders_enabled`.
    *   Turning it on requests notification permission the first time
        (CUJ 10).
    *   Next to it: the permission-denied state with a button to the system
        settings, and "Reminders scheduled through <date>".

##### 48. `apps/mobile/lib/features/protocols/widgets/protocols_day_view.dart` (Modify, Phase 5 part)

*   **Proposed Changes**: The "Reminders are off on this device" banner with
    "Allow" (CUJ 12), under the conditions in D5.

##### 49. `apps/mobile/lib/features/protocols/widgets/protocol_reminders_settings.dart` (Create) and `apps/mobile/lib/features/settings/widgets/privacy_settings_screen.dart` (Modify)

*   **Proposed Changes**: A "Supplement reminders" tile under the existing
    tile for the Supplements lock settings. It holds the device switch and a
    status screen showing only the notification permission and "Reminders
    scheduled through <date>".

##### 50. `apps/mobile/lib/l10n/app_en.arb` and generated `app_localizations*.dart` (Modify/Regenerate)

*   **Proposed Changes**: The reminder copy, the permission strings, the
    banner, and the settings tile and screen.

##### 51. Tests (Create)

*   `apps/mobile/test/features/protocols/protocol_reminder_plan_test.dart`:
    *   grouping (CUJ 1);
    *   dropping filled times (CUJ 2);
    *   off-cycle (CUJ 3);
    *   the mixed reminders-on and reminders-off case;
    *   untimed planned doses excluded;
    *   the cap and the horizon formula (CUJ 11);
    *   id stability and the negative range;
    *   daylight-saving-change days.
*   `apps/mobile/test/features/protocols/protocol_reminder_scheduler_test.dart`:
    *   the diff against a fake plugin, and no `cancelAll`;
    *   one run at a time under overlapping triggers;
    *   the device switch off;
    *   lock-independent text;
    *   the payload contents;
    *   initialization requests no permission.
*   `apps/mobile/test/features/protocols/protocol_reminder_tap_test.dart`: a
    tap routes through the lock gate to the right date, from a cold start and
    from resume.
*   `apps/mobile/test/features/protocols/protocols_day_view_test.dart`
    (Modify): the CUJ 12 banner.

#### Phase 6: Agent planned-day and status reads

##### 52. `apps/server/src/agent-protocols.ts` (Modify, Phase 6 part)

*   **Proposed Changes**: The two reads, with the operation ids, parameters,
    response shapes and errors in D6.
    *   Rows are filtered in SQL by user and entity type before the core runs.
        There is no full-table load.
    *   Responses carry statuses and counts only.

##### 53. `apps/server/src/agent-mcp.ts` (Modify)

*   **Proposed Changes**: The MCP tools `agent_list_protocol_planned_days` and
    `agent_list_protocol_day_statuses`, with the same parameters.

##### 54. Generated contract (Regenerate)

*   **Proposed Changes**: As file 26, for the new routes.

##### 55. Tests (Modify)

*   `apps/server/test/agent-protocols.test.mjs`:
    *   range limits and each 400 error;
    *   the required `today`;
    *   future dates allowed on planned days and rejected on Day Statuses;
    *   filters;
    *   summary vs `doses` detail.
*   `apps/server/test/agent-mcp-parity.test.mjs`: the new tools match REST.

##### 56. `docs/designs/SITEMAP.md` and this spec (Modify)

*   **Proposed Changes**: Status → Current once Phase 6 merges.

### Verification Plan

*   **Build**: `flutter build apk --debug`, plus an iOS simulator build
    (`flutter build ios --simulator --debug`), run by hand at Phase 5,
    because no CI job builds the platforms.
*   **CI gate**: `pnpm ci:local --changed` green on every phase. The jobs that
    must pass:
    *   `golden` (Phases 1, 2 and 6);
    *   `mobile` (every phase);
    *   `contract` (Phases 2 and 6);
    *   `js` and `sync` (Phases 2 and 6).
*   **Cross-language**: every m36 case passes in both languages. A case that
    passes in one and not the other fails the `golden` job.
*   **Standing scenarios**: kill-and-reopen during "Log all planned" (file
    34); sync convergence with same-day versions (file 28).
*   **Manual, on a device, at Phase 5**:
    *   CUJ 1 at a near-future minute on an iPhone and an Android phone;
    *   with the lock on, the notification text checked on the lock screen;
    *   a rest-timer notification still opens its exercise;
    *   permission denied (CUJ 10) and the second-phone banner (CUJ 12);
    *   a reboot on Android, after which a reminder still fires;
    *   a timezone change in system settings, after which the app is
        reopened, moves the next reminder (CUJ 8).
*   **Success**: the motivating user's stack from The Problem, entered as three
    Protocols ("Daily", "Skin" and "Shoulder"), produces the reminders and Day
    Statuses of CUJs 1 to 7 over two weeks of use on a device.

--------------------------------------------------------------------------------

<!-- Provenance: Indicates initial structural drafting via EGM. -->

*Drafted with EGM*
