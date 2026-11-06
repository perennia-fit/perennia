# User Profile and First-Open Onboarding

*   **Author:** Leonardo Pinheiro
*   **Status:** In Review
*   **Date:** 2026-11-04

Read with: [AGENTS.md](../../AGENTS.md) (invariants and conventions),
[CONTEXT.md](../../CONTEXT.md) (terms), [ARCHITECTURE.md](../../ARCHITECTURE.md) (layering,
contract, sync), and [DESIGN.md](../../DESIGN.md) (UI tokens and components).

--------------------------------------------------------------------------------

## Overview

This spec adds a **User Profile**: an optional, synced record of who the user is and what they
train for. It is grouped into six sections, and each one can be left empty:

| Section | Holds |
|---|---|
| About you | Sex used for default reference ranges, birth year, height |
| Training Goals | What the user trains for, from a fixed list |
| Experience | A beginner / intermediate / advanced level for each Focus the user picks |
| Training setup | Equipment the user has access to, days per week available, usual session length |
| Health & limitations | Injuries, movements to avoid, conditions (capped free text) |
| General Notes | Anything else the user wants an agent to know (capped free text) |

It also adds two ways to fill the record:

1.  **A Profile screen** under Account & app, where every section can be read and edited.
2.  **A first-open onboarding** of at most three screens:
    *   About you, with units and week start day;
    *   Training Goals and Experience;
    *   Training setup.

    It can be skipped from its first screen. Once it is done or skipped it does not come back on
    that install, and it never shows on an install that already holds a User Profile section.

Agents read and write the User Profile through REST and MCP, with the same validation as the app.
Every change is recorded in the Activity Log and can be undone. Nothing limits which agent reads
which field. Instead, the Profile screen carries a disclosure line that names who can read it.

The spec also replaces the AGENTS.md rule "No onboarding wizards, no sample data; the empty Home
Screen's CTA is the onboarding" with a rule that allows one optional onboarding that can be
skipped from its first screen. No sample data stays a rule.

## The Problem

Perennia holds nothing about the user as a person. It has no sex, age, height, goals, experience
or constraints. Three readers need some of this:

*   **Lab results.** A lab-results spec is planned but not yet written. Its one need from this
    spec is stated here so this spec stands alone: where a lab report prints no reference range,
    it shows a general default range, and commonly published default ranges are given by sex and
    by age band. So it needs the user's sex and their age on the sample date. Without them, a
    result with no printed range is shown with no range at all.
*   **Agents.** Agents connected to a Synced Mode account already create Workout Templates,
    Routines, Nutrition Goals and Protocols. An agent writing a training plan has to know the
    user's goals, experience, available equipment and time, and injuries. Today it has to ask the
    user each time, or guess. Some of this can be inferred from logged history, but that history
    says nothing about an injury, a goal or the equipment at home.
*   **People, later.** A human-coaching feature may come later. It is not designed here, but the
    record and its disclosure copy must not assume the reader is always an AI agent.

The maintainer's target persona is a hybrid athlete training for longevity: often advanced in one
discipline and new to another, often taking compounds that affect hormones, and careful about
what they share. That judgement leads to three requirements:

*   Every field is optional.
*   The user can see who can read the record.
*   Experience cannot be a single level for the whole person.

**Why onboarding, and why now.** The current AGENTS.md rule assumes the user installs the app on
the gym floor and wants to log a set immediately. The maintainer's judgement is that the target
persona usually installs it at home and spends time setting up Routines, Protocols and nutrition
before their first Workout. A short onboarding that can be skipped from its first screen asks for
the core facts at the moment the user is already setting up. The friction the old rule guarded
against is handled by making skipping one tap and final for that install.

Two existing mechanisms do not fit:

*   **`UserSettings` cannot hold the User Profile.** It syncs as one row under last-writer-wins,
    and the agent settings write rebuilds that row from the eight account-level fields it knows
    (`mergeSettings` and `buildSettingsPayload` in `apps/server/src/agent-settings.ts`). An agent
    settings write, or an older app build, would silently erase any User Profile fields stored on
    it.
*   **Body Weight already has a home.** It is a Metric with history and a Trend, and Body Tracker
    records it. Weight changes every week; the facts in the User Profile change rarely. So weight
    stays a Metric and is not part of the User Profile or onboarding.

## Goals

1.  **A User Profile record with six independent sections.** Each field can be:
    *   *unset*: never answered;
    *   *none*: answered as "nothing applies", for example "no limitations";
    *   set to a value.

    Agents can tell these three states apart.
2.  **Sections sync independently.**
    *   Edits to two different sections on two offline devices both survive the next Sync Run.
    *   An edit to the same section on two devices resolves by last-writer-wins, and the losing
        version can be recovered from the Activity Log.
3.  **A stable read contract for other specs.** The fields, their units, and which ones may be
    empty are fixed by this spec. Age is derived from birth year at a given date and never
    stored.
4.  **Agent parity.**
    *   One read operation and one partial batch-write operation, over REST and MCP, with the same
        validation as the app.
    *   Absent means unchanged; explicit null means clear.
    *   Every write is one Activity Log Batch, undoable from the app and through agent undo.
5.  **Two-tier validation in one shared module**, golden-vectored in Dart and TypeScript.
    *   Hard rejects for impossible values, for example a birth year in the future or text over
        its cap. The full list is in the Validation table.
    *   Soft warnings for improbable values, for example an age over 100.
    *   Agents receive the warnings in the write response, as for every agent write.
6.  **A first-open onboarding.**
    *   At most three screens, each with **Skip this** and **Skip all**.
    *   A sign-in link on screen 1 for users who already have an account.
    *   Shown at most once per install, and never on an install that already holds a User
        Profile section.
    *   It asks for no OS permission, imports nothing, creates no Routine and adds no sample data.
7.  **A rule for later inline asks.** A feature that needs one missing field may ask for it once,
    in context, and never again after it is dismissed on any device on the account. This spec
    sets that rule only. The first feature that asks specifies its ask and the synced record of
    its dismissal.
8.  **Accurate disclosure.** One line per mode, Local-only Mode and Synced Mode, as written in
    Disclosure copy. The Synced line names the server's operator and any connected agent as
    readers, and says that change history on the server is kept for up to 180 days
    (`ACTIVITY_LOG_RETENTION_DAYS` in `apps/server/src/activity-log-retention.ts`).
9.  **Health text is redacted from agent history.** Agent reads of the Activity Log show that
    Health & limitations or General Notes changed, and who changed them, but not the text.
10. **Lifecycle.**
    *   Account deletion removes the User Profile.
    *   Backup and restore include it, merge-only.
    *   Logs and crash reports never contain its values.

## Non-Goals

*   **Agent key scopes or per-field "hide from agents" settings.** Every connected agent can read
    every field. Scopes may come in a later spec.
*   **Weight or body fat in the User Profile or in onboarding.** Weight stays a Metric that Body
    Tracker records; body fat is not asked.
*   **Nutrition targets computed from the User Profile.** The app is a logbook, not a coach: it
    records what the user planned and did, and leaves advice to the user and their agents. An
    in-app energy calculation would also be a new golden-vectored analytics computation. Agents
    can already read the User Profile and write Nutrition Goals.
*   **Any in-app use of Training Goals, Experience, Training setup or Health & limitations.** In
    this spec they exist for agents (and later coaches). The app does not change its suggestions
    based on them.
*   **Medications in Health & limitations.** Compounds and Doses belong to Protocols. The Health &
    limitations editor points there instead of storing the same fact twice.
*   **Inline asks.** No ask card and no dismissal record ship here (see Goal 7).
*   **Onboarding beyond the user and general preferences.** See Goal 6.
*   **New Equipment registry items.** The registry already has cardio items (`spinBike`,
    `skiErg`, `rope`, `step`). Anything it lacks, such as a rower, treadmill or pool, goes in
    General Notes.
*   **Onboarding or User Profile analytics** of any kind, including completion or skip counts.
*   **The Official Service operator's legal obligations** for health information: privacy policy
    wording and regional law. This spec names them and does not address them.
*   **The lab-results behaviour itself**, such as which range to show when sex is unset. This
    spec only supplies the fields.

## Open Questions

None. The privacy review of the disclosure copy is a pre-merge step under Non-Functional
Requirements.

## Critical User Journeys (CUJs)

### CUJ 1: New user skips everything

*   **Given**: A fresh install in Local-only Mode.
*   **When**: The user opens the app and taps **Skip all** on screen 1.
*   **Then**:
    *   The app sets the device setting `onboardingDone` and writes no User Profile section.
    *   The user lands on Today.
    *   Onboarding never shows again on this install.

### CUJ 2: New user fills About you and skips the rest

*   **Given**: A fresh install in Local-only Mode.
*   **When**: On screen 1 the user does the following, then taps **Skip this** on screens 2 and 3:
    1.  picks Imperial units;
    2.  sets sex to Female, birth year to 1990 and height to 5 ft 6 in;
    3.  taps **Next**.
*   **Then**:
    *   Screen 1 saves the unit-system setting and then the About you section, with height
        stored as `{ value: 66, unit: "in" }`, in the order given under Onboarding flow.
    *   `onboardingDone` is set when the user leaves screen 1.
    *   No Training Goals, Experience or Training setup section exists. All of them read as
        *unset*.

### CUJ 3: The app is killed mid-onboarding

*   **Given**: The user saved screen 1 and is on screen 2.
*   **When**: The app is killed and reopened.
*   **Then**:
    *   Onboarding does not show again, because `onboardingDone` was set when the user left
        screen 1.
    *   The About you section is intact.
    *   If the app is killed on screen 1 before the user taps anything, onboarding shows again
        on reopen.

### CUJ 4: Existing user reinstalls and signs in from screen 1

*   **Given**:
    *   An account whose server holds a filled User Profile.
    *   A fresh install of the app.
*   **When**: The user taps **Already use Perennia? Sign in** on screen 1 and signs in.
*   **Then**:
    *   Onboarding closes, sets `onboardingDone`, writes no section, and opens Today. It does not
        wait for a Sync Run.
    *   The first Sync Run then pulls the account's User Profile in the background, and the
        Profile screen shows it.

### CUJ 5: Existing user fills onboarding on a second device, then signs in

*   **Given**:
    *   The account's About you on the server is: Male, 1988, 180 cm.
    *   On a fresh second device, the user ignores the sign-in link, fills only sex (Male) on
        screen 1, and finishes onboarding in Local-only Mode.
*   **When**: The user signs in from Settings, and the first Sync Run pushes the device's About
    you row and pulls the server's.
*   **Then**:
    *   The two rows have different ids. The device's row is newer, so every device and agent
        reads About you as Male, unset, unset.
    *   The account's earlier row (Male, 1988, 180 cm) stays in the table and in the Activity
        Log. The user can enter the values again on the Profile screen.
    *   This is the accepted cost recorded under Risks & Mitigations. The sign-in link on
        screen 1 is the path that avoids it.

### CUJ 6: An agent writes, and the user undoes it

*   **Given**: A Synced Mode user with one agent key.
*   **When**: The agent calls `batchWriteAgentProfile` with:
    *   Training Goals: strength and longevity;
    *   Training setup: days per week 4.

    The user then undoes that change from the Activity feed.
*   **Then**:
    *   The write is one Batch with two section changes.
    *   Undo restores both sections to their prior state, on the device and on the server.
    *   If either section changed in between, the whole undo is refused with the existing
        "Couldn't undo: changed since" message (`trainingUndoConflict`), and neither section is
        reverted.

### CUJ 7: An agent sends an improbable value

*   **Given**: An agent key.
*   **When**: The agent writes birth year 1915.
*   **Then**:
    *   The write applies, as every agent write with soft warnings does.
    *   The response has `warnings: [{ section: "aboutYou", field: "birthYear", rule:
        "birth_year.improbable_age", message: ... }]`, for the agent to confirm with the user.
    *   Writing birth year 2031 (a future year) is a hard reject: status 422 and nothing written.

### CUJ 8: Health text is cleared

*   **Given**: A Synced Mode user has a knee injury noted in Health & limitations.
*   **When**: The user clears the text and selects **None**.
*   **Then**:
    *   The section reads as *none*.
    *   The user's Activity feed shows "Profile · Health & limitations updated". The change's
        before-image, which the device keeps for undo, still holds the old text.
    *   `GET /agent/activity` shows that Health & limitations changed, and who changed it, but
        no text.

### CUJ 9: Two devices edit different sections offline

*   **Given**: Phone A and Phone B are both synced and both offline.
*   **When**: A edits Training setup, and B edits General Notes. Both reconnect.
*   **Then**: Both edits survive, because they are different section rows.

### CUJ 10: Account deletion

*   **Given**: A Synced Mode user with a User Profile.
*   **When**: The account is deleted and purged.
*   **Then**: The server's User Profile section rows are deleted with the user row.

## Technical Plan (Architecture)

### Terms

These terms are new. They are added to CONTEXT.md in PR 1.

| Term | Definition |
|---|---|
| **User Profile** | The optional, synced record of who the user is and what they train for. It has six sections: About you, Training Goals, Experience, Training setup, Health & limitations, and General Notes. It is distinct from Record Profile (a per-exercise headline-record choice). Every field may be unset. The app itself reads only About you; the rest exists for agents. |
| **Training Goal** | One outcome the user trains for, chosen from a fixed list (for example longevity or strength). Distinct from Nutrition Goal, from a Metric's goal direction, and from Focus, which is the discipline a Workout is performed under. |

The existing **Equipment** definition is widened to read: "The tool or setup normally used for
an Exercise, or that the user has access to, as listed in the User Profile's Training setup.
Both use the same registry ids, and both may hold unknown ids, shown as labels."

"Profile" alone is used only in UI copy (the tile, the screen title). Code, the contract, sync and
this spec's prose use `user_profile` / `UserProfile` / "User Profile".

### Data model

There is one new synced entity. It does not touch `UserSettings`.

```text
user_profile_sections          one live row per section (newest wins)
  id            text  PK       UUIDv7 (device) / random UUID (server, agent write)
  section       text           about_you | training_goals | experience |
                               training_setup | health_limitations | general_notes
  values_json   text           section values, shape below
  + standard sync columns: sync_device_id, sync_previously_synced, updated_at, deleted_at
```

On the server, the table carries `user_id` referencing `user.id` with `onDelete: cascade`. The
sync payload is `{ section, values }`.

**Why random ids and "newest per section".** In Local-only Mode, a device has no user id. The
server primary key is global, and a push whose id another user already owns is dropped. So a
fixed id like `profile:<section>:<userId>` cannot be created before sign-in. `UserSettings` and
`NutritionGoals` have the same constraint, and their pattern is reused:

1.  **Reads** take the live row with the greatest `updated_at` for each section. Ties are broken
    by `id`, matching `agent-nutrition-goals.ts`.
2.  **Writes** update that row in place. A section row is created only when none exists.
3.  A device that pulls a newer row for a section it already holds reads that row from then on.
    The older row stays in the table, unread, as Nutrition Goals rows do.

**Section values.** These are the sync payload and golden-vector names. In every section, `null`
means *unset*.

| Section | `values` shape | *none* |
|---|---|---|
| `about_you` | `sex`: `"female"` \| `"male"` \| null; `birth_year`: integer \| null; `height`: `{ value: number, unit: "cm" \| "in" }` \| null | not applicable |
| `training_goals` | `goals`: TrainingGoalId[] \| null | `[]` |
| `experience` | `levels`: `{ focus_id: string, level: "beginner" \| "intermediate" \| "advanced" }[]` \| null | `[]` |
| `training_setup` | `equipment`: EquipmentId[] \| null; `days_per_week`: integer \| null; `session_minutes`: integer \| null | `equipment: []` means bodyweight only |
| `health_limitations` | `text`: string \| null; `none`: boolean (never null, default `false`) | `none: true`, with `text: null` |
| `general_notes` | `text`: string \| null | not applicable |

Rules for the values:

*   **TrainingGoalId** is one of `longevity`, `strength`, `muscle_gain`, `body_composition`,
    `endurance_performance`, `mobility`, `general_fitness`. The list is unordered and has no
    duplicates. Chip labels: Longevity, Strength, Muscle gain, Body composition, Endurance
    performance, Mobility, General fitness.
*   **Experience levels.** Each level has a one-line meaning shown in the UI:
    *   Beginner: "Under a year of regular training in this Focus."
    *   Intermediate: "One to three years."
    *   Advanced: "More than three years."

    `focus_id` is any non-empty Focus id, with no foreign key, following `Exercises.focusIds`.
    Starter Focuses are seeded with fixed ids, so they match across installs. An entry whose
    Focus is archived is kept and hidden in the device UI.
*   **EquipmentId** is any non-empty string of at most 64 characters. Ids in
    `ExerciseEquipment.known` (`apps/mobile/lib/domain/training/training_dimensions.dart`) are
    shown with their labels. Other ids are kept and shown as the id, as CONTEXT.md allows for
    Equipment. The Training setup editor offers every registry id except `bodyweight`, so `[]`
    is the only way to say "bodyweight only".
*   **Height** is stored as entered.
    *   Metric entry stores centimetres, to one decimal place.
    *   Imperial entry of feet and inches stores the total in inches, to one decimal place. For
        example, 5 ft 6 in is stored as 66 in.
    *   Conversion happens on read only, at exactly 2.54 cm per inch.
*   **Age is never stored.** `ageAt(date)` is `date.year - birth_year`, using the calendar year of
    `date` in the device's local time. It is accurate to ±1 year. That is enough to place a user
    in an age band, which is how commonly published default ranges are given.
*   **Health & limitations normalisation.** Setting non-null `text` sets `none` to `false`.
    Setting `none: true` sets `text` to `null`. When one save sets both, `none: true` wins and
    `text` becomes `null`. An explicit `none: null` means `false`. The device and the agent merge
    both apply this before validating, so `none: true` with text cannot be stored.
*   **Tolerant reads.** Push does no domain validation, so a stored row can hold anything.
    *   On the device, a field of the wrong JSON type reads as unset, and an unknown enum entry
        is dropped from the typed getters. So is an Equipment id the rules reject (empty, over
        64 characters, or a duplicate), because the user couldn't see or fix what blocked their
        Save of Days per week. An unknown Equipment id within the rules is kept.
    *   In the agent read, a field of the wrong JSON type reads as `null`, a non-string list
        entry is dropped, and every string id is kept, including one the rules reject, so the
        agent sees it and the merge keeps it (see Agent surface, Validation).
    *   Neither read throws, and merges run over the tolerantly read values.

**Save semantics.** One rule holds on the device and in the agent write:

*   A field absent from a save is unchanged. A field given as `null` is cleared. A list replaces
    the whole list.
*   A section with no row is *unset*. A save that would create a row with every field `null` (or
    `none: false` and `text: null`) creates nothing.
*   A save that changes nothing on an existing row writes nothing: `updated_at` stays, and there
    is no Activity Log entry or Sync Nudge. Otherwise a retry would make undo of the earlier
    Batch read as changed since, although no value changed.
*   Once a row exists, clearing every field keeps the row, with all fields unset. The user never
    deletes the record, only empties it.
*   The **None** choice on the Profile screen writes `[]` or `none: true`. Selecting nothing
    writes nothing, so it stays *unset*.

### Sync

The entity syncs through the existing per-row path:

*   It is added to `SYNC_PUSH_ENTITIES` and `SYNC_PULL_ENTITIES`.
*   Pushes received by the server apply row-level LWW on `updated_at`, following the
    `nutrition_goals` push path.
*   On the device it uses the same apply path as `nutrition_goals`: a pulled row is inserted, or
    it replaces the local row with the same id if it is newer.

**No domain validation at push.** The server parses the payload shape only: `section` is one of
the six names and `values` is an object. Domain rules run on the device before every write, and
in the agent route. This matches every other synced entity. The server has no way to reject a
single pushed change: a change it does not accept stays pending on the device and stalls every
later Sync Run (`RepositorySyncCycleRunner` stops after two passes with no progress). A rule
check at push would turn a rule disagreement between app versions into a sync outage.

**Rollout.** The server ships first, as it did for every earlier entity. The app adds no guard.
A newer app syncing to a Self-Hosted Deployment that has not been upgraded fails its push,
because the server's entity enum rejects the new entity, and Sync Runs fail until the server is
upgraded. The release note tells self-hosters to upgrade the server first. This is recorded under
Risks & Mitigations.

A build from before this change skips the unknown `user_profile_sections` entity but still
advances its pull cursor past those changes, so after upgrading it would never pull the rows it
skipped. The `from < 67` migration step therefore also runs `UPDATE sync_states SET pull_cursor =
NULL` (when that table exists), and the first Sync Run after the upgrade is a full pull. This is
the same step as `from < 66` in `apps/mobile/lib/data/local/app_database.dart`
(docs/designs/compound-purposes.md, "Older clients").

### Onboarding gate

Onboarding shows when both of these hold:

1.  The device setting `onboardingDone` is `false`.
2.  No live `user_profile_sections` row exists.

`onboardingDone` is a device-level, never-synced field of `AppSettings`, next to
`onlineFoodLookups` and `showProtocolsOnToday`. It lives in the local `settings.json`, so erase
all data keeps it, as it keeps every device setting. On a fresh device the gate runs before
sign-in, so a synced record of "onboarding done" could not stop onboarding from showing the first
time. Syncing it would change nothing, and it would bring the undo and erase conflicts described
in Alternative T.

Installs from before this feature have no `onboardingDone` key. These are only maintainer and
test builds, because nothing has shipped. They see onboarding once and can skip it in one tap.

**When it runs.** Today renders first, as it does now. Once both checks resolve (one settings
read and one existence query), onboarding is pushed over Today as a full-screen route if the gate
is true. Nothing waits on the network and no spinner is shown. The gate runs once per app start.

### Onboarding flow

```text
[1 About you + units]     Next / Skip this --> set onboardingDone --> [2]
                          Skip all ----------> set onboardingDone --> Today
                          Sign in -----------> sign-in flow; on success set onboardingDone --> Today
                                                             on cancel --> back to [1]
[2 Goals + Experience]    Next / Skip this --> [3]       Skip all --> Today      Back --> [1]
[3 Training setup]        Done / Skip this --> Today     Skip all --> Today      Back --> [2]
```

*   **Done.** `onboardingDone` is set the first time the user leaves screen 1 by **Next**,
    **Skip this**, **Skip all** or a successful sign-in. From then on, killing the app never
    brings onboarding back.
*   **Saving.** **Next** writes only the fields entered on that screen, following Save
    semantics. If nothing was entered, it writes nothing, like **Skip this**. Screens 2 and 3
    each save as one Activity Log Batch.
*   **Back.** Screens 2 and 3 have a back arrow. Going back to a saved screen and saving again
    writes another Batch.
*   **Sign in from screen 1** opens the existing sign-in flow. When it succeeds, onboarding sets
    `onboardingDone`, writes no section, and opens Today. The first Sync Run then runs in the
    background as for any sign-in. When the user cancels, they return to screen 1.
*   **Screen 1 save order.**
    1.  Save each changed setting (unit system, week start day) through the existing
        `SettingsController` setters. Each setter saves on its own, so this is one Activity Log
        Batch per changed setting.
    2.  Write the About you section as one Batch, if any of its fields was entered.
    3.  Set `onboardingDone`. This is a device setting, not an Activity Log Batch, so no undo
        can bring onboarding back.

Screen contents:

| Screen | Fields |
|---|---|
| 1 About you | Units (Metric / Imperial), week start day, sex (Female / Male / Not set), birth year, height |
| 2 Training Goals + Experience | Training Goal chips (multi-select); for each active Focus, a level selector that defaults to Not set |
| 3 Training setup | Equipment chips (the registry without `bodyweight`), days per week (1 to 7), usual session length in minutes |

Health & limitations and General Notes appear only on the Profile screen.

### Profile screen

The Profile screen opens from a **Profile** tile in the Account & app sheet, between account
status and Settings. Under its title it shows the disclosure line for the current mode. It lists
the six sections as cards. Each card shows its values or "Not set", and tapping it opens an
editor sheet. The Health & limitations and General Notes editors show a character counter against
their cap.

### Disclosure copy

There is one line per mode, shown under the Profile screen title and in the onboarding footer.
`{host}` is the host name of the server the user signed in to. The app has no separate way to
recognise the Official Service, and the host name stays accurate for self-hosters.

| Mode | Copy |
|---|---|
| Local-only Mode | "Stored on this phone and in its backups. If you sign in, it syncs to your account, where the server's operator and any agent you connect can read it." |
| Synced Mode | "Synced to {host}. The server's operator and any agent you connect can read it. Change history on the server is kept for up to 180 days." |

"In its backups" covers Android Auto Backup and iCloud device backup, both on by default for the
app's data, and Perennia's own Auto-backup to a folder the user picks.

Two more lines appear in specific editors:

*   **Health & limitations and General Notes** add: "Agent activity history shows that this
    section changed, not the text."
*   **Health & limitations** adds: "Medications and supplements belong in Protocols."

The copy says "the server's operator" rather than naming a company. That stays true for
self-hosters, and for a future coach feature. It matches ARCHITECTURE.md (Sync): the server
stores and reads synced rows, and nothing is end-to-end encrypted.

### Agent surface

The REST surface is generated from the route definitions. The MCP tools are registered by hand.
The agent surface uses camelCase names (`aboutYou`, `birthYear`, `daysPerWeek`,
`sessionMinutes`, `focusId`), as every agent schema does. The route maps them to the snake_case
section values above.

| | REST | MCP tool | CLI command |
|---|---|---|---|
| Read | `GET /agent/profile` (`readAgentProfile`) | `agent_read_profile` | `read-profile` |
| Write | `POST /agent/profile/batch-write` (`batchWriteAgentProfile`) | `agent_batch_write_profile` | `update-profile` |

*   **Read** returns `{ sections: { aboutYou, trainingGoals, experience, trainingSetup,
    healthLimitations, generalNotes } }`. Each section is `{ values, updatedAt }`, or `null` when
    it has no row or every field in its row is unset. Experience entries are
    `{ focusId, level }`, described as "see GET /agent/focuses; an id not listed there names an
    archived Focus."
*   **Write request:** `{ idempotencyKey, updatedAt?, sections: { <section>?: { <field>?: value
    | null } } }`, following `AgentSettingsBatchWriteRequestSchema`. The schema is strict:
    unknown sections or fields, wrong JSON types and non-integer counts return the route's 400
    validation response. At least one field is required.
*   **Merge.** The server merges the given fields into the current values of each named section,
    following Save semantics and the Health & limitations normalisation, and writes the whole
    section row. That is one Activity Log Batch with `batchId` equal to `idempotencyKey`, as the
    settings write does.
*   **Validation** runs through the shared module on the merged values of each named section,
    with `referenceYear` set to the server's current UTC year.
    *   Any hard reject returns status 422 with `AgentProfileBatchWriteErrorResponseSchema`,
        following `AgentSettingsBatchWriteErrorResponseSchema`, and nothing is written. Its
        `code` is `agent_profile_batch_write_failed` and each error is `{ section, field, rule,
        message }`.
    *   A stored value the rules reject is part of the merged values, so it blocks a write of
        its section, even one that doesn't name that field. The error names the field, and the
        agent clears or corrects it in the same write. Only a push can store such a value. The
        merge never drops it, because that would erase a value the write didn't name.
    *   A section given with no fields names nothing: it is not merged, validated or written.
    *   A section whose merged values equal its tolerantly read values is validated but not
        written (see Save semantics). Its warnings are returned. If no section changed, there is
        no Batch, so sending the same key again runs as a new write, not a replay.
    *   Otherwise the write applies, and the 200 response is `{ accepted: true, duplicate,
        idempotencyKey, batchId, serverClock, profile, warnings }`. `profile` is the read shape
        after the write. Each warning is `{ section, field, rule, message }`.
    *   A replay of the same `idempotencyKey` returns the same envelope with `duplicate: true`.
        On a replay, `profile` is the current read shape and `warnings` are recomputed by
        validating the after-images of the Batch's Activity Log entries. Nothing stores the
        original response, so a section the first write left unchanged returns no warnings.
    *   When the store is unavailable, the route returns 503 with code
        `agent_profile_unavailable`, following `agent_settings_unavailable`.
*   **Contract diff:** two new operations and their schemas, and a new `user_profile_sections`
    value in the `SyncPushRequest.entity` and `SyncPulledChange.entity` enums. No other existing
    operation changes.
*   **Agent undo.** `user_profile_sections` is added to `UNDOABLE_ENTITY_REGISTRY`
    (`apps/server/src/agent-activity.ts`), so undo through the agent surface works as for other
    entities.
*   **Activity redaction.** In `listAgentActivity` (REST and the MCP tool `agent_list_activity`),
    any change to a `user_profile_sections` row whose section is `health_limitations` or
    `general_notes` has its before and after `values` replaced with `{ "redacted": true }`. The
    section is read from either image, and values are also redacted when no image gives a
    readable section, so redaction fails closed. A null image stays null. The entity, section,
    actor and time are kept. The device's Activity Log is not redacted. Redaction limits what
    agents read in history; it is not access control.
*   **Tool descriptions**, verbatim:
    *   `agent_read_profile`: "Read the user's User Profile: About you, Training Goals,
        Experience, Training setup, Health & limitations and General Notes. Every agent
        connected to this account can read it. Values are what the user entered, not medical
        advice."
    *   `agent_batch_write_profile`: "Change fields in the user's User Profile. Only the fields
        you send change, null clears a field, and a list replaces the whole list. Improbable
        values are saved and returned as warnings to confirm with the user. Each call is one
        Activity Log Batch the user can undo."

### Validation

There is one module per language, golden-vectored. `reference_year` is an input to every vector,
so results do not depend on the clock. The device passes its local calendar year; the agent
route passes the server's UTC year. Height limits are in centimetres. An inch value is converted
at exactly 2.54 cm per inch, with no rounding, before it is compared.

| Field | Hard reject (rule) | Soft warning (rule) |
|---|---|---|
| `birth_year` | > reference_year (`birth_year.future`); < reference_year - 130 (`birth_year.too_old`) | age < 13 or > 100 (`birth_year.improbable_age`) |
| `height` | value <= 0 (`height.non_positive`); > 300 cm (`height.too_tall`); unit not cm or in (`height.unit`) | < 120 cm or > 220 cm (`height.improbable`) |
| `days_per_week` | < 1 or > 7 (`days_per_week.range`) | none |
| `session_minutes` | < 1 or > 600 (`session_minutes.range`) | > 240 (`session_minutes.improbable`) |
| `goals` | unknown id (`goals.unknown`); duplicate (`goals.duplicate`) | none |
| `equipment` | empty or over 64 characters (`equipment.invalid`); duplicate (`equipment.duplicate`) | none |
| `levels` | level not in the set (`levels.unknown_level`); empty `focus_id` (`levels.invalid_focus`); two entries for one Focus (`levels.duplicate_focus`) | none |
| `health_limitations.text` | > 1,000 UTF-16 code units (`text.too_long`) | none |
| `general_notes.text` | > 2,000 UTF-16 code units (`text.too_long`) | none |
| `sex` | value outside the set (`sex.unknown`) | none |

Messages, returned with each issue and shown in the UI:

| Rule | Message |
|---|---|
| `birth_year.future` | "Birth year can't be in the future." |
| `birth_year.too_old` | "Birth year can't be more than 130 years ago." |
| `birth_year.improbable_age` | "That makes you {age}. Check the birth year." |
| `height.non_positive` | "Height must be more than zero." |
| `height.too_tall` | "Height must be 300 cm (118.1 in) or less." |
| `height.unit` | "Height must be in cm or in." |
| `height.improbable` | "A height of {height} is unusual. Check it." |
| `days_per_week.range` | "Days per week must be 1 to 7." |
| `session_minutes.range` | "Session length must be 1 to 600 minutes." |
| `session_minutes.improbable` | "Sessions over 4 hours are unusual. Check the length." |
| `goals.unknown` | "Unknown Training Goal." |
| `goals.duplicate` / `equipment.duplicate` | "Each item can appear once." |
| `equipment.invalid` | "Equipment ids must be 1 to 64 characters." |
| `levels.unknown_level` | "Level must be Beginner, Intermediate or Advanced." |
| `levels.invalid_focus` | "Each level needs a Focus." |
| `levels.duplicate_focus` | "Each Focus can have one level." |
| `text.too_long` | "Keep this under {limit} characters." |
| `sex.unknown` | "Sex must be Female, Male or Not set." |

In the UI, a soft warning opens the existing confirm dialog used for soft warnings (the
`AlertDialog` that `BodyTrackerScreen` shows for an improbable reading): its title is "Check this
value", its content is the warning message, and its actions are **Edit** and **Save anyway**.
**Save anyway** saves; **Edit** returns to the field.

### Read contract for other specs

Other features read the User Profile only through `UserProfileRepository.watch()`. It returns a
`UserProfile` value with:

*   a typed getter per field, each nullable;
*   `ageAt(DateTime)`, which returns an integer or null.

The planned lab-results spec is expected to use `sex` and `ageAt(sampleDate)`. This spec
guarantees those names, types and nullability. The read contract is provisional until that spec
is approved: if it needs a change, the change is made in this spec, in the same pull request.

### Lifecycle

*   **Account deletion.** The server table cascades from `user`.
*   **Backup and restore.** The table is included in the portable archive. Restore is merge-only:
    a row is imported if its id is new, and LWW by `updated_at` applies if it exists.
*   **Logs and crash reports.**
    *   On the server, `sections` and `values` join `TRAINING_DATA_KEYS` in
        `apps/server/src/observability.ts`, in a commented block like the Protocols one.
        `shouldFilterKey` replaces the whole subtree under a filtered key, and `payload`,
        `changes`, `beforeimage` and `afterimage` are already filtered, so sync payloads and
        Activity Log images are covered today.
    *   The agent route bodies are one new carrier. A failed query is another: Drizzle's
        `DrizzleQueryError` puts the bound params, and so the section values, into `message` and
        `stack`, and the scrubber filters by key only. `serializeErrorForObservability`, which
        the logger and Sentry both use, therefore reduces any error with `query`, `params` or
        `parameters` to its type, a fixed message, and the `code` and constraint name of the
        error and its `cause`.
    *   The raw request body is the third, on any route, `/sync/push` included: by default the
        Sentry SDK attaches it to an event as the string `request.data`, whatever
        `sendDefaultPii` says, and the key filter can't read a string. So `sdk.init` sets
        `httpIntegration({ maxIncomingRequestBodySize: "none" })`, and `beforeSend` always
        removes `request.data` as the backstop.
    *   Sentry keeps an event's exceptions under `exception.values`, so `beforeSend` exempts that
        one path from the `values` filter and scrubs its items. An item's `value`, the message,
        stays filtered.
    *   On the device, `client_crash_reporting.dart` already replaces every exception value with
        `filteredCrashValue` and keeps only allow-listed breadcrumb keys, so it needs no change.
    *   Logs record only ids and section names.

### Invariants touched

| Invariant | How it is preserved |
|---|---|
| Sets self-describing / values as entered | Height is stored with the unit it was entered in, and converted on read. |
| Derived analytics never stored | Age is computed from birth year on read. Nothing about the User Profile is derived and stored. |
| Delete = archive; no cascading deletes | The user only clears fields. A section row is never deleted by the app. A Focus archived after an Experience entry keeps the entry. The only cascade is account purge, which is the existing deletion path. |
| Restore is merge-only | The new table joins the existing merge-only archive import. |
| Local writes never block on the network | All writes are local Drift writes. Onboarding never waits for sync, including after a sign-in. |
| Silent LWW with recoverable losers | Per-row LWW on each section row, with losers in the Activity Log. No dialog. |
| One shared two-tier validation module | The new rules live in the shared module, are golden-vectored, and reach agents as `warnings` on an applied write, as for every agent write. |
| No behavioral analytics | Nothing about onboarding or the User Profile is counted or sent. |

### Repository doc changes

*   **AGENTS.md** (PR 2). The bullet "No onboarding wizards, no sample data; the empty Home
    Screen's CTA is the onboarding." is replaced with:

    > Onboarding is optional: one first-open flow of at most three screens, skippable from its
    > first screen, shown at most once per install, never with sample data, and never asking for
    > an OS permission, importing data or creating a Routine. The empty Home Screen's CTA is
    > still how a new user starts logging.

*   **AGENTS.md** (PR 1). The Screen map gains **Profile** under Account & app.
*   **CONTEXT.md** (PR 1). The two new terms, the widened Equipment definition, and a pointer
    from Record Profile ("not the User Profile").
*   **ARCHITECTURE.md (Sync)** (PR 1). The new entity, and the rule that the server does no domain
    validation at push.
*   **DESIGN.md.** The disclosure line component (PR 1) and the onboarding screen component
    (PR 2).

### Staging

The work is one spec in two implementation pull requests, listed in the Detailed Implementation
Plan: PR 1 ships the record, the Profile screen and the agent surface; PR 2 ships onboarding and
the AGENTS.md onboarding rule change.

## Alternatives Considered

### Storage and sync

#### Alternative A: Add the User Profile fields to `UserSettings`

*   **Pros**:
    *   No new table or sync entity.
    *   The agent settings surface already exists.
*   **Cons**:
    *   `UserSettings` syncs as one opaque row under whole-row LWW. The agent settings write
        rebuilds that row from its eight known fields, so an agent settings write, or an older
        app build, would silently erase the User Profile fields.
    *   A theme change on one device and a Training Goals edit on another would be one LWW
        contest, and one of them would lose.
    *   Health text would travel with every settings read.
*   **Reason for Rejection**: Silent data loss, which is the failure the invariants exist to
    prevent.

#### Alternative B: A new single-row User Profile entity with whole-row LWW

*   **Pros**:
    *   The least new machinery. It copies the settings singleton path.
*   **Cons**:
    *   Concurrent edits to different sections on two devices lose one of the edits.
    *   Undo refuses once the row has changed since the change being undone. With one row, any
        later edit to any section blocks undo of an agent's write.
*   **Reason for Rejection**: It breaks the promise that independent sections sync and undo
    independently (CUJ 6, CUJ 9).

#### Alternative C: One row per field or list item, set-merged

*   **Pros**:
    *   Per-field LWW and per-field undo.
    *   No concurrent edit is ever lost.
*   **Cons**:
    *   Roughly ten rows per user instead of six, and every read assembles the record from keyed
        rows.
    *   List membership needs its own add and remove rules, in both languages.
*   **Reason for Rejection**: The record is edited rarely, usually by one person on one device.
    Per-section LWW covers that case without list-merge rules in two languages.

#### Alternative D: Fixed ids per section (`profile:<section>:<userId>`)

*   **Pros**:
    *   Two devices always write the same row, so there is no "newest per section" read rule.
*   **Cons**:
    *   A Local-only device has no user id, so it cannot create the id before sign-in.
    *   It would need a new step that re-keys rows at sign-in.
*   **Reason for Rejection**: It cannot be built for the offline-first default. Random ids with
    "newest per section" follow the existing Nutrition Goals pattern.

#### Alternative E: Fill unset fields from the account's row at first sync

*   **Pros**:
    *   A second device's first About you row would not hide the account's other answers
        (CUJ 5).
*   **Cons**:
    *   A Sync Run pushes before it pulls, so a device-side fill never sees the account's row
        before its own row is pushed and marked synced.
    *   A server-side fold through `SyncPushResponseSchema.merged` exists only for Metrics. It
        needs an alias table, an advisory lock and a device adopt step.
    *   Either way it needs its own clock rule so the merged row is read as newest.
*   **Reason for Rejection**: The case needs a user with an account who ignores the sign-in link
    on screen 1. Shadowing keeps the earlier row recoverable, as for `UserSettings` and Nutrition
    Goals.

#### Alternative F: A per-entity push gate for servers that have not been upgraded

*   **Pros**:
    *   A newer app would keep syncing other entities to an older Self-Hosted Deployment.
*   **Cons**:
    *   Held-back rows stay pending, so `RepositorySyncCycleRunner` would still fail every Sync
        Run unless `hasPendingChanges()`, `watchPendingChangeCount()` and the outbound tables all
        exclude them.
    *   It needs a server-advertised entity list, a persisted copy on the device, and a hand-edit
        of the Dart client.
    *   Every earlier entity shipped server-first without one.
*   **Reason for Rejection**: It is a sync-protocol feature for every entity, not a User Profile
    feature. If version skew needs handling, it gets its own spec.

### Privacy

#### Alternative G: Per-field "share with agents" toggles, or agent key scopes

*   **Pros**:
    *   An access control, not only disclosure.
*   **Cons**:
    *   It is the first place agents would see less than the app, which cuts against agent
        parity.
    *   Every agent read and undo path would need to respect it.
    *   Users would need to understand it.
*   **Reason for Rejection**: The maintainer chose disclosure only for now, to keep the first
    version simple and parity intact. Scopes stay possible later without changing this record.

#### Alternative H: An "Advanced" tab for sensitive fields

*   **Pros**:
    *   Keeps the main screen short.
*   **Cons**:
    *   Where a field sits on screen does not change who can read it. Presenting it as a privacy
        measure would mislead users.
*   **Reason for Rejection**: Not a privacy control. The sensitive sections instead get their own
    disclosure lines and are kept out of onboarding.

#### Alternative I: Leave health history visible to agents

*   **Pros**:
    *   No special case in the activity read.
*   **Cons**:
    *   Text the user cleared from Health & limitations would stay readable by every connected
        agent for 180 days.
*   **Reason for Rejection**: Redacting the two free-text sections costs one rule in one read
    path and removes most of that exposure.

#### Alternative J: Purge cleared health text from the Activity Log

*   **Pros**:
    *   Cleared text is gone from history.
*   **Cons**:
    *   The Activity Log is append-only, and it is how sync losers are recovered and undo works.
*   **Reason for Rejection**: It breaks the recoverable-loser invariant. Redaction plus a stated
    retention period is the trade-off chosen instead.

#### Alternative K: Exclude the database from OS backup

*   **Pros**:
    *   "Stored only on this phone" would be true in Local-only Mode.
*   **Cons**:
    *   It changes Android and iOS backup for all of the app's data, not only the User Profile.
*   **Reason for Rejection**: Out of scope for this spec. The Local-only copy says "and in its
    backups" instead.

### Fields

#### Alternative L: Free text for Training Goals and Experience

*   **Pros**:
    *   Agents can read prose.
    *   No list to maintain.
*   **Cons**:
    *   No validation, so the record would drift.
    *   Agents get no stable values to branch on.
    *   It invites health detail into fields not labelled for it.
*   **Reason for Rejection**: A seven-item list and a three-level scale are small to maintain,
    and Experience has to be keyed by Focus anyway. Free text is kept where structure would
    mislead: Health & limitations and General Notes.

#### Alternative M: A fixed list for Health & limitations

*   **Pros**:
    *   Structured and filterable.
*   **Cons**:
    *   Injuries and conditions vary too widely for a list.
    *   A medical-sounding list invites the app to look like it gives medical advice.
    *   It would overlap with Protocols.
*   **Reason for Rejection**: Capped free text, with an explicit None, records what the user
    means with one field and one flag.

#### Alternative N: One experience level for the whole person

*   **Pros**:
    *   One question.
*   **Cons**:
    *   The target persona is often advanced in one discipline and a beginner in another. An
        agent given one level plans at the wrong level for one of them.
*   **Reason for Rejection**: The level is set per Focus instead, reusing an existing term.

#### Alternative O: Weight in the User Profile, or asked in onboarding

*   **Pros**:
    *   One place for "about you".
*   **Cons**:
    *   It duplicates the Body Weight Metric, which has history and a Trend.
    *   Weight changes weekly, so a profile field would go stale.
    *   Saving it from onboarding as a Metric Reading seeds Body Fat too, re-seeds an archived
        Body Weight, and adds Batches to screen 1.
*   **Reason for Rejection**: Weight stays a Metric, and Body Tracker records it.

#### Alternative P: Full date of birth

*   **Pros**:
    *   Exact age.
*   **Cons**:
    *   More identifying, and every connected agent can read it.
    *   Default ranges are commonly given by age band, so the extra precision would go unused.
*   **Reason for Rejection**: Collect the minimum. Birth year gives age to ±1 year.

#### Alternative Q: A third value for sex

*   **Pros**:
    *   More inclusive wording.
*   **Cons**:
    *   The field exists to choose a default reference range, and default ranges are commonly
        published for female and male only. A third value would need the lab-results spec to
        say which range it shows.
*   **Reason for Rejection**: The field is labelled for its purpose ("Sex used for default
    reference ranges"), and Not set is always available. The lab-results spec defines what Not
    set shows.

#### Alternative R: Store height in canonical centimetres

*   **Pros**:
    *   One unit on read.
*   **Cons**:
    *   Imperial entries round-trip with rounding.
    *   It departs from the project's "stored as entered" rule.
*   **Reason for Rejection**: Store as entered, convert on read.

#### Alternative S: Hard-reject Equipment ids outside the registry

*   **Pros**:
    *   Agents cannot store typos.
*   **Cons**:
    *   A newer app that adds a registry id would sync it to older devices, and every later edit
        of Training setup on those devices would fail.
    *   It needs a TypeScript copy of `ExerciseEquipment.known` and a test to keep it in step.
    *   CONTEXT.md already allows unknown Equipment ids as labels.
*   **Reason for Rejection**: Validate shape and duplicates only, as exercise writes do.

### Onboarding

#### Alternative T: A synced record that onboarding is done

*   **Pros**:
    *   A second device or a reinstall would not show onboarding again once it had synced.
*   **Cons**:
    *   On a fresh device the gate runs before sign-in, so nothing has synced yet and onboarding
        shows anyway. The record only matters if the gate is checked again after sign-in.
    *   Pushing it needs Activity Log entries. Undo of the Batch that holds it would either fail
        or tombstone it, and on a device with no section rows the tombstone would bring
        onboarding back on every device. Erase-all would do the same.
*   **Reason for Rejection**: A device setting gives the same first-open behaviour with no sync,
    undo or erase rules. The first feature with an inline ask specifies the synced dismissal
    record it needs.

#### Alternative U: Keep the AGENTS.md rule; no onboarding at all

*   **Pros**:
    *   No first-open friction.
*   **Cons**:
    *   Agents, the main reader of Training Goals, Experience and Training setup, would get
        values only from users who find the Profile screen on their own.
    *   In the maintainer's judgement, the target persona sets up at home before training,
        when a three-screen flow they can skip costs one tap at most.
*   **Reason for Rejection**: The maintainer chose to change the rule because agents need these
    values and one-tap skipping keeps the friction the rule guarded against low.

#### Alternative V: Show onboarding only after sign-in

*   **Pros**:
    *   It knows the account state, so onboarding never shows to an existing account.
*   **Cons**:
    *   Local-only users, the default, would never see it.
*   **Reason for Rejection**: Offline-first is the default. A sign-in link on screen 1 handles
    users who already have an account.

#### Alternative W: Check the gate again after the first Sync Run that follows a sign-in

*   **Pros**:
    *   An empty account would still get onboarding after signing in from screen 1.
*   **Cons**:
    *   A first Sync Run for an existing account pulls history in 100-row windows and can take
        minutes. Onboarding would need a waiting state, a timeout and a failure path.
    *   If that Sync Run failed, an existing user would be shown onboarding again.
*   **Reason for Rejection**: Signing in from screen 1 closes onboarding. A user with an empty
    account fills the User Profile from the Profile screen.

#### Alternative X: An authored-data condition in the gate

*   **Pros**:
    *   An install from before this feature, with logged history, would never see onboarding.
*   **Cons**:
    *   It queries several tables at each start until onboarding is done, and the list has to
        track every authored domain (Workouts, Food Entries, Doses, Meals and more) to be
        right.
    *   Nothing has shipped, so the only such installs are maintainer and test builds.
*   **Reason for Rejection**: Those installs see onboarding once and can skip it in one tap.

### Scope and rollout

#### Alternative Y: Separate specs for the record, onboarding and the agent surface

*   **Pros**:
    *   Smaller documents.
*   **Cons**:
    *   Agent parity forbids an app capability without its agent operation.
    *   Onboarding's gate depends on the record.
    *   Splitting them leaves each spec unable to state its own invariants.
*   **Reason for Rejection**: One spec, delivered as two pull requests.

#### Alternative Z: Confirm soft warnings before an agent write applies

*   **Pros**:
    *   An improbable value never lands without a second request.
*   **Cons**:
    *   ARCHITECTURE.md says of soft warnings: "The write proceeds; the caller confirms." Every
        existing agent write applies and returns `warnings`, so agents would have to learn a
        second convention for one endpoint.
    *   It adds a request flag, a response status and a test matrix.
*   **Reason for Rejection**: The agent write follows the existing pattern.

--------------------------------------------------------------------------------

## Non-Functional Requirements

*   **Security & Privacy**:
    *   The User Profile holds health information.
    *   The disclosure copy names every reader, and agent history redacts the two free-text
        sections.
    *   Logs and crash reports never contain values (see Lifecycle).
    *   **Pre-merge steps for PR 1:** the maintainer decides whether a privacy reviewer reads the
        disclosure copy, and confirms that the Official Service privacy policy covers the User
        Profile before the first hosted release that contains PR 1.
*   **Performance & Latency**:
    *   Every write is a local Drift write, confirmed within one frame.
    *   The onboarding gate is one settings read and one existence query. Today renders before
        it resolves, so it adds no network call and no spinner.
*   **Rollout & Rollback**:
    *   The server ships first.
    *   The app cannot be downgraded in place. App stores do not allow it, and Drift refuses to
        open a newer schema. So rolling the app back means shipping a fix release on top of the
        additive migration.
    *   Rolling the server back leaves the device's User Profile changes pending, and Sync Runs
        fail until the server is upgraded again (see Risks & Mitigations).

## Risks & Mitigations

| Risk | Impact | Mitigation or accepted limit |
|---|---|---|
| Two devices edit the same section before syncing | One side's edit is not read | Accepted: per-section LWW. The losing version is recoverable from the Activity Log. |
| A second device's first section row is read as newest (CUJ 5) | The account's other answers in that section are hidden | Accepted: the older row stays in the table and the Activity Log. The sign-in link on screen 1 avoids it. |
| A newer app syncs to a server that has not been upgraded | Every Sync Run fails until the server is upgraded | Accepted, as for every earlier entity. The release note says to upgrade a Self-Hosted Deployment first. |
| Age is accurate to ±1 year | A user near an age-band edge may get the neighbouring band's default range | Accepted: birth year is the minimum the user is asked for. The lab-results spec states how it shows a default range. |
| A hosted release ships before the privacy policy covers health information | Legal exposure for the Official Service operator | The pre-merge step under Security & Privacy. |

--------------------------------------------------------------------------------

### Additional Resources

*   [docs/designs/protocol-schedules-and-reminders.md](protocol-schedules-and-reminders.md) sets
    the rule that no OS permission is requested outside its feature.
*   Code patterns reused:
    *   `apps/server/src/agent-settings.ts` (agent read and write, envelope and idempotency);
    *   `apps/server/src/agent-nutrition-goals.ts` (newest live row per key);
    *   `UNDOABLE_ENTITY_REGISTRY` in `apps/server/src/agent-activity.ts`;
    *   `AppSettings` device-level fields in
        `apps/mobile/lib/features/settings/repositories/settings_repository.dart`.

### Future Improvements

*   **Agent key scopes**, for example to exclude Health & limitations from a key. This record
    needs no change to support them.
*   **Inline asks**, specified by the first feature that needs one, with its synced dismissal
    record.
*   **In-app use of Training Goals and Experience**, for example ordering suggestions. Each such
    use would need its own spec.
*   **A human-coaching reader.** The Synced copy says "the server's operator and any agent you
    connect can read it". A coach would be added to both mode lines.

--------------------------------------------------------------------------------

## Detailed Implementation Plan

There are two pull requests, in merge order. Each lists every file it touches, numbered from 1
within that PR. A schema version or golden-vector id below is "the next free one" at the time
of writing: Drift schema 67, drizzle migration `0037`, golden vector `m41`. If another change
takes one first, the implementer takes the next one and corrects this spec in the same pull
request.

Every change a user, agent or self-hoster can see adds a `CHANGELOG.md` line under
`## [Unreleased]`, `Added`. Both PRs are minor-bump changes.

### PR 1: User Profile record, Profile screen and agent surface

| # | File | Action | Why |
|---|---|---|---|
| 1 | `packages/golden-vectors/vectors/m41-user-profile-validation.json` | Create | Shared validation vectors |
| 2 | `packages/golden-vectors/vectors/m41-user-profile-validation.schema.json` | Create | Schema for file 1 |
| 3 | `packages/golden-vectors/vectors/README.md` | Modify | List m41 |
| 4 | `apps/mobile/lib/domain/profile/user_profile.dart` | Create | Dart domain types and `ageAt` |
| 5 | `apps/mobile/lib/domain/profile/user_profile_validation.dart` | Create | Dart validation module |
| 6 | `apps/mobile/test/domain/user_profile_validation_test.dart` | Create | Dart golden-vector runner |
| 7 | `apps/mobile/test/domain/golden_vector_ownership_test.dart` | Modify | Register the domain owner |
| 8 | `apps/server/src/agent-validation.ts` | Modify | TypeScript validation module |
| 9 | `apps/server/test/agent-validation.golden.test.mjs` | Modify | TypeScript golden-vector runner |
| 10 | `apps/mobile/lib/data/local/app_database.dart` | Modify | Drift table and migration |
| 11 | `apps/mobile/drift_schemas/app_database/drift_schema_v67.json` | Create (generated) | Schema snapshot |
| 12 | `apps/mobile/test/generated_migrations/app_database/schema_v67.dart` | Create (generated) | Migration test schema |
| 13 | `apps/mobile/test/generated_migrations/app_database/schema.dart` | Modify (generated) | Snapshot index |
| 14 | `apps/mobile/test/data/schema_snapshot_migration_test.dart` | Modify | v66 to v67 step test |
| 15 | `apps/mobile/lib/data/repositories/user_profile_repository.dart` | Create | Section reads and writes |
| 16 | `apps/mobile/lib/data/repositories/training_repositories.dart` | Modify | Part directive, undo images, erase |
| 17 | `apps/mobile/lib/features/sync/repositories/sync_repository.dart` | Modify | Push, pull and full re-sync |
| 18 | `apps/mobile/lib/features/activity/repositories/activity_feed_repository.dart` | Modify | Feed labels |
| 19 | `apps/mobile/lib/data/repositories/portable_archive_repository.dart` | Modify | Backup and restore |
| 20 | `apps/mobile/lib/features/profile/controllers/profile_controller.dart` | Create | Riverpod controller |
| 21 | `apps/mobile/lib/features/profile/widgets/profile_screen.dart` | Create | Profile screen |
| 22 | `apps/mobile/lib/features/profile/widgets/profile_section_editors.dart` | Create | Six editor sheets |
| 23 | `apps/mobile/lib/features/home/widgets/home_screen.dart` | Modify | Profile tile |
| 24 | `apps/mobile/lib/app.dart` | Modify | Profile route |
| 25 | `apps/mobile/lib/l10n/app_en.arb` | Modify | Copy |
| 26 | `apps/mobile/lib/l10n/app_localizations*.dart` | Modify (generated) | `flutter gen-l10n` output |
| 27 | `apps/server/src/db/schema.ts` | Modify | Postgres table |
| 28 | `apps/server/drizzle/0037_user_profile.sql` | Create (generated) | Migration |
| 29 | `apps/server/drizzle/meta/` (journal and snapshot) | Modify (generated) | Drizzle metadata |
| 30 | `apps/server/src/sync.ts` | Modify | Entity, store, pull and push |
| 31 | `apps/server/src/app.ts` | Modify | Push dispatch and agent routes |
| 32 | `apps/server/src/agent-profile.ts` | Create | Agent schemas, store and handlers |
| 33 | `apps/server/src/index.ts` | Modify | Store wiring and re-exports |
| 34 | `apps/server/src/agent-mcp.ts` | Modify | MCP tools |
| 35 | `apps/server/src/agent-activity.ts` | Modify | Undo registry and redaction |
| 36 | `apps/server/src/observability.ts` | Modify | Log scrubbing |
| 37 | `packages/contract/src/agent-skill-reference.ts` | Modify | Command and tool names |
| 38 | `agent-skills/perennia/scripts/prn-agent.mjs` | Modify | CLI commands |
| 39 | `packages/contract/openapi.json` | Modify (generated) | Contract |
| 40 | `packages/contract/src/agent-client.ts` | Modify (generated) | TypeScript client |
| 41 | `apps/mobile/lib/api/perennia_api_client.dart` | Regenerate (no diff) | The Dart client carries no agent operations and types `entity` as a string, so the regeneration leaves it unchanged |
| 42 | `agent-skills/perennia/references/api-operations.md` | Modify (generated) | Skill reference |
| 43 | `apps/server/test/agent-profile.test.mjs` | Create | Agent route tests |
| 44 | `apps/server/test/user-profile-sync.test.mjs` | Create | Push and pull tests |
| 45 | `apps/server/test/sync-convergence.test.mjs` | Modify | Two-device convergence |
| 46 | `apps/server/test/agent-mcp.test.mjs` | Modify | Tool list and redaction through MCP |
| 47 | `apps/server/test/observability.test.mjs`, `apps/server/test/observability-sentry-sdk.test.mjs` | Modify, Create | Scrubbed keys; the real SDK sends no request body |
| 48 | `apps/server/test/account-deletion-purge.test.mjs` | Modify | Purge removes rows |
| 49 | `apps/mobile/test/data/user_profile_repository_test.dart` | Create | Repository tests |
| 50 | `apps/mobile/test/features/sync/sync_repository_test.dart` | Modify | Device push and pull |
| 51 | `apps/mobile/test/data/erase_all_data_test.dart` | Modify | Erase guard |
| 52 | `apps/mobile/test/data/portable_archive_repository_test.dart` | Modify | Archive guard |
| 53 | `apps/mobile/test/features/profile/profile_screen_test.dart` | Create | Widget and accessibility tests |
| 54 | `CONTEXT.md` | Modify | Terms |
| 55 | `ARCHITECTURE.md` | Modify | Sync section |
| 56 | `DESIGN.md` | Modify | Disclosure line component |
| 57 | `AGENTS.md` | Modify | Screen map |
| 58 | `CHANGELOG.md` | Modify | Release note |
| 59 | `agent-skills/perennia/scripts/prn-code.mjs` | Modify | Portable client keeps identical method names |
| 60 | `agent-skills/perennia/SKILL.md` | Modify | `read-profile` and `update-profile` examples |

**Verifies:** Verification Plan items V1 to V7 and V9.

#### Shared validation and golden vectors (files 1 to 9)

*   **File 1.** Top level: `{ "name": "m41-user-profile-validation", "domain":
    "user-profile-validation", "schemaVersion": 1, "schema":
    "m41-user-profile-validation.schema.json", "limits": {...}, "cases": [...] }`, following
    `m39-meal-validation.json`.
    *   `limits` holds every number in the Validation table, `trainingGoalIds`, `sexes`,
        `experienceLevels` and `cmPerInch: 2.54`.
    *   Each case is `{ name, input: { referenceYear, section, values }, expected: { accepted,
        errorRules, warningRules } }`, with `values` in the snake_case section shape.
    *   Cases cover every Validation table row on both sides of each boundary:
        *   birth year: `referenceYear`, `referenceYear + 1`, `referenceYear - 130`,
            `referenceYear - 131`, and ages 12, 13, 100 and 101;
        *   height in cm: 0, 119.9, 120, 220, 220.1, 300, 300.1;
        *   height in inches: 47.2 (warns), 47.3, 86.6, 86.7 (warns), 118.1, 118.2 (rejected);
        *   an unknown height unit;
        *   days per week 0, 1, 7, 8; session minutes 0, 1, 240, 241, 600, 601;
        *   Health & limitations text at 1,000 and 1,001 UTF-16 code units, including a case
            where an astral-plane character counts as 2; General Notes at 2,000 and 2,001;
        *   an unknown goal, duplicate goals, an empty and a 65-character equipment id,
            duplicate equipment, an unknown equipment id that is accepted;
        *   an unknown level, an empty `focus_id`, two levels for one Focus;
        *   an unknown sex.
*   **File 2.** JSON Schema for file 1, following `m40-compound-purposes.schema.json`.
*   **File 3.** Add the m41 section, in the style of the m39 and m40 sections.
*   **File 4.**
    *   `enum UserProfileSection { aboutYou, trainingGoals, experience, trainingSetup,
        healthLimitations, generalNotes }`, with wire names as in the Data model.
    *   `enum TrainingGoalId`, `enum ExperienceLevel`, `enum ProfileSex { female, male }`.
    *   `ProfileHeight { double value; HeightUnit unit /* cm | inch */ }` with `inCentimetres`.
    *   `ExperienceEntry { String focusId; ExperienceLevel level }`.
    *   One immutable value class per section, with nullable fields and `toJson` / `fromJson` in
        the wire shape. `HealthLimitationsValues.none` is a non-null `bool`.
    *   `UserProfile`, holding the six optional sections, with getters `sex`, `birthYear`,
        `height`, `goals`, `experienceLevels` (`List<ExperienceEntry>?`), `equipment`,
        `daysPerWeek`, `sessionMinutes`, `healthText`, `healthNone`, `generalNotesText`, and
        `int? ageAt(DateTime date)`, which returns `date.toLocal().year - birthYear`.
    *   `mergeUserProfileSectionValues(UserProfileSection section, Map<String, Object?> current,
        Map<String, Object?> changes)`, a pure function that implements Save semantics and the
        Health & limitations normalisation over the tolerantly read `current`. A key in `current`
        that this build doesn't know is kept, so saving on an older build doesn't erase a field a
        newer one wrote. It is the only place that logic lives on the device; file 15 calls it.
    *   `isUserProfileSectionUnset(UserProfileSection section, Map<String, Object?> values)`,
        the test for *unset* under Save semantics.
*   **File 5.**
    *   `UserProfileValidationResult validateUserProfileSection(UserProfileSection section,
        Map<String, Object?> values, {required int referenceYear})`.
    *   It reuses the shape of `settings_validation.dart`: a `UserProfileValidationIssue` with
        `field`, `rule`, `message` and optional `limit`, and a result with `errors`,
        `warnings`, `accepted` and `throwIfRejected()`.
    *   Limits live in a `UserProfileValidationLimits` class, following
        `SettingsValidationLimits`. Messages are the strings in the Validation table.
    *   Equipment ids are checked for length and duplicates only.
    *   Text length is String `.length` (UTF-16 code units). `{height}` formats as `<value>
        <unit>` with no trailing `.0`, matching JavaScript number formatting (for example
        `110 cm`, `47.2 in`). `{limit}` is plain digits and `{age}` is reference year minus birth
        year.
    *   A field of the wrong JSON type is skipped as unset, because the schema or the tolerant
        read has already handled it. Each rule is reported at most once per field. Issues appear
        in the order of the Data model's fields and, within a field, of the Validation table.
*   **File 6.** Runs every case in file 1 and asserts `accepted`, `errorRules` and
    `warningRules`, that `limits` equal `UserProfileValidationLimits`, and the exact message text
    of `birth_year.improbable_age`, `height.improbable` and `text.too_long`. It also unit-tests
    the merge helper, tolerant `fromJson` and `ageAt`.
*   **File 7.** Add `'user-profile-validation': 'test/domain/user_profile_validation_test.dart'`.
*   **File 8.** Add `validateUserProfileSection(section, values, { referenceYear })` with the same
    rules, rule names and messages, and `USER_PROFILE_VALIDATION_LIMITS`, next to
    `validateAgentSettings`. Export both through `apps/server/src/index.ts` (file 33).
*   **File 9.** Add `["user-profile-validation", (vectorCase) =>
    validateUserProfileSection(...)]` to `VALIDATORS_BY_DOMAIN`, with a `limits` deepEqual and the
    same three exact messages as file 6. This test is already in
    `test:golden-vectors` and in the golden path filters of `tools/ci-local.mjs` and
    `.github/workflows/ci.yml`, so neither file changes.

#### Device schema and repositories (files 10 to 19)

*   **File 10.**
    *   Add the `UserProfileSections` table (`id`, `section`, `valuesJson`, plus the standard
        sync columns) and add it to `tableNames`.
    *   `schemaVersion` becomes 67. The migration from 66 creates the table behind the existing
        `_tableExists` guard, and writes no rows to it. The `from < 67` step also runs
        `UPDATE sync_states SET pull_cursor = NULL` when that table exists, for the reason under
        Sync › Rollout.
    *   The table docstring says why the User Profile is not on `UserSettings`, and gives the
        newest-per-section read rule.
*   **Files 11 to 13.** Run `dart run tool/drift_schema_snapshots.dart` from `apps/mobile`.
*   **File 14.** Add a v66 to v67 step: a populated v66 database gains an empty
    `user_profile_sections` table, keeps its other rows, and has its pull cursor cleared.
*   **File 15.** `part of 'training_repositories.dart'`. Repositories are the only layer that
    touches this table; this one owns section reads and writes.
    *   `Stream<UserProfile> watch()` reads the newest live row per section.
    *   `Future<bool> hasAnySection()` is an existence query for any live row.
    *   `Future<void> saveSection(UserProfileSection section, Map<String, Object?> changes,
        {String? batchId})`:
        1.  merges `changes` into the newest row's values, following Save semantics and the
            Health & limitations normalisation;
        2.  validates the merged values through file 5 with the local calendar year, and throws
            `UserProfileValidationException` on a hard error. Warnings are not checked here; the
            controller asks first (file 20);
        3.  returns without writing if no row exists and every merged field is unset;
        4.  updates the newest row in place, or creates one with a UUIDv7;
        5.  appends the change to one Activity Log Batch, with actor `user`.
    *   A clear is a `saveSection` call with `null` for the field.
*   **File 16.**
    *   Add the `part` directive and expose `userProfile`.
    *   Add `user_profile_sections` to `_currentImageFor` and `_writeImageFor`, so device undo
        restores a section row from its before-image.
    *   Add the table to the `eraseTableNames` list that `eraseAllData` walks. Erase keeps
        `settings.json`, so it does not affect the onboarding setting that PR 2 adds.
*   **File 17.**
    *   Add `_pushPendingUserProfileSectionsWithClient`, called right after
        `_pushPendingNutritionGoalsWithClient` at both of its existing call sites
        (`pushPendingLoggedSets` and `pullLoggedSetChanges`), following it line for line.
    *   Add the table to `_outboundSyncActivityTables`.
    *   Apply pulled rows on the `nutrition_goals` apply path.
    *   Add `_markPreviouslySyncedUserProfileSectionRowsAbsentFromSnapshotDeleted`, following the
        existing `…RowsAbsentFromSnapshotDeleted` functions, so a full re-sync tombstones rows
        the server no longer holds.
*   **File 18.** For `user_profile_sections`, `affectedEntitySummary` reads `section` from the
    change's after-image (or before-image) and renders "Profile · {section label} updated". The
    six labels are About you, Training Goals, Experience, Training setup, Health & limitations
    and General Notes. A section row's first write uses the same verb, "updated", because the
    user sees one record. A Batch whose entries are all `user_profile_sections` renders
    "Profile · {labels joined by ", "} updated", for example "Profile · Training Goals, Training
    setup updated". With no readable section it renders "Profile updated". These labels are
    English constants, like every other label in `activity_feed_repository.dart`, which has no
    localization.
*   **File 19.** Export the table. Import merge-only: a row is inserted if its id is new,
    otherwise LWW by `updatedAt`. An archive from before schema 67 has no such file and imports
    with no rows, through `_mayBeAbsentFromArchive`; a schema 67 archive without it is refused.

#### Profile screen (files 20 to 26)

*   **File 20.**
    *   Watches `userProfile.watch()`, the current mode (Local-only Mode or Synced Mode) and the
        signed-in server URL from the auth state.
    *   Exposes `ProfileDisclosureMode { localOnly, synced }` and `host`, the URL's host name.
    *   `save(section, changes)` validates first. If there are soft warnings, it returns them, and
        the screen shows the confirm dialog from the Validation section. **Save anyway** calls
        `saveSection`.
*   **File 21.** `ProfileScreen.routeName = '/profile'`.
    *   The disclosure line for the current mode sits under the title.
    *   Six section cards follow, each showing its values or "Not set". Unknown equipment ids
        show as the id.
    *   Tapping a card opens that section's editor sheet.
*   **File 22.** One editor per section. Every editor has targets of at least 48 dp, a semantics
    label on every control, and styling from theme tokens only.
    *   **About you:**
        *   a sex segmented control (Female / Male / Not set);
        *   a birth year picker from 130 years before the current local year to the current
            local year;
        *   height in centimetres to one decimal place, or feet plus inches to one decimal place
            under Imperial, stored as total inches.
    *   **Training Goals:** the seven chips with their labels, plus **None**.
    *   **Experience:**
        *   one row per active Focus, with a Beginner / Intermediate / Advanced / Not set
            selector and the level's one-line meaning;
        *   entries for archived Focuses are hidden and kept;
        *   **None**.
    *   **Training setup:**
        *   equipment chips from `ExerciseEquipment.known` without `bodyweight`, plus **None**,
            and any stored unknown ids as extra selected chips;
        *   a days-per-week stepper (1 to 7, Not set);
        *   session length in minutes (Not set allowed).
    *   **Health & limitations:** a text field with a character counter against the 1,000 cap,
        a **None** toggle, the medications line and the agent-history line. Turning **None** on
        clears the text; typing text turns **None** off.
    *   **General Notes:** a text field with a character counter against the 2,000 cap, and the
        agent-history line.
*   **File 23.** Add a **Profile** tile between account status and Settings in the Account & app
    sheet, opening `ProfileScreen.routeName`.
*   **File 24.** Register `ProfileScreen.routeName` in the `routes` map.
*   **Files 25 and 26.** Add the strings given verbatim in the Technical Plan:
    *   the two disclosure lines (with `{host}`) and the two editor lines;
    *   the level meanings and the Training Goal chip labels;
    *   the validation messages and the confirm dialog's title and buttons.

    The feed labels are not in this list: they stay English constants in file 18. Section and
    field labels are the names used in the Overview and Data model, in sentence
    case for field labels (for example "Birth year", "Days per week"). Any other string is
    written by the implementer and reviewed in the pull request. Then run `flutter gen-l10n`.

#### Server (files 27 to 42, 59 and 60)

*   **Files 27 to 29.** Add `userProfileSections` with:
    *   `id` (primary key);
    *   `userId`, referencing `user.id` with `onDelete: "cascade"`;
    *   `payload` (jsonb), `deviceId`, `updatedAt`, `deletedAt`, `receivedAt`;
    *   the index `user_profile_sections_user_updated_at_index` on `(userId, updatedAt)`,
        following `nutrition_goals_user_updated_at_index`.

    Generate the migration with `corepack pnpm --filter @perennia/server db:generate`. It is additive.
*   **File 30.**
    *   Add `USER_PROFILE_SECTIONS_SYNC_ENTITY = "user_profile_sections"` to
        `SYNC_PUSH_ENTITIES` and `SYNC_PULL_ENTITIES`.
    *   Add the `SyncStore` methods and their Drizzle implementations, following
        `nutrition_goals`: push with row-level LWW, including the tenant-isolation check that
        drops a pushed id another user owns.
    *   The push parses `{ section, values }` with a Zod schema (`section` one of the six names,
        `values` an object) and runs no domain validation.
    *   Add the pull cursor filter, select and row map, and include the table in snapshot mode.
    *   Give the entity a rank in `syncEntitySortRank` next to `nutrition_goals`. It has no
        parent, so it gets no entry in `PULL_PARENT_REFERENCES`.
*   **File 31.**
    *   Add `case USER_PROFILE_SECTIONS_SYNC_ENTITY` to the push dispatch `switch`, next to
        `NUTRITION_GOALS_SYNC_ENTITY`.
    *   Register both agent routes with `app.openapi`, next to the settings routes, and accept
        an `agentProfileStore` in the `createApp` options.
    *   The write handler sends the Sync Nudge after an applied write, as the settings handler
        does.
*   **File 32.**
    *   Zod and OpenAPI schemas: `AgentProfileSchema`, `AgentProfileBatchWriteRequestSchema`
        (strict), `AgentProfileBatchWriteResponseSchema`,
        `AgentProfileBatchWriteErrorResponseSchema` (422, following the settings error schema),
        and the 503 `agent_profile_unavailable` schema.
    *   `AgentProfileStore`, with `read({ userId })` and `batchWrite({ userId, deviceId,
        request })`, and `createDrizzleAgentProfileStore(db)`. `deviceId` is `agent:<keyId>`,
        which only the route knows.
    *   `read` takes the newest live row per section, ordered by `updated_at` and then `id`,
        maps it to camelCase, and returns `null` for a missing or all-unset row.
    *   `batchWrite`:
        1.  replays by `idempotencyKey` (equal to `batchId`) as `agent-settings.ts` does,
            returning `duplicate: true`;
        2.  merges each named section following Save semantics and the Health & limitations
            normalisation;
        3.  validates with file 8 and the server's UTC year, returning the 422 error on any hard
            reject;
        4.  in one transaction, updates the newest row in place or inserts a row with a random
            UUID, and appends one Activity Log Batch with before and after images and actor
            `agent`, for each section whose merged values differ from its current values;
        5.  returns the applied response with `warnings`.
*   **File 33.** Build the profile store next to the settings store, pass it to `createApp` and
    to `AgentMcpServerOptions`, and re-export `validateUserProfileSection` and
    `USER_PROFILE_VALIDATION_LIMITS`.
*   **File 34.** Add `profileStore` to `AgentMcpServerOptions`. Register `agent_read_profile` and
    `agent_batch_write_profile`, with the descriptions given verbatim in the Technical Plan,
    calling file 32's store. The write tool's result follows `writeSettingsBatchToolResult`,
    including the Sync Nudge.
*   **File 35.**
    *   Add `user_profile_sections` to `UNDOABLE_ENTITY_REGISTRY`. Undo restores the
        before-image and refuses the whole Batch when the current image differs from the
        recorded after-image, as the existing entries do.
    *   In `listAgentActivity`, for changes whose entity is `user_profile_sections`, read the
        section from either image. When it is `health_limitations` or `general_notes`, or when
        no image gives a readable section, replace the before and after `values` with
        `{ "redacted": true }`. A null image stays null. The MCP tool `agent_list_activity` uses
        the same read, so it is redacted too.
*   **File 36.** Add `sections` and `values` to `TRAINING_DATA_KEYS`, in a commented block like
    the Protocols one, saying they carry User Profile values in agent route bodies.
*   **File 37.** Add `readAgentProfile: "read-profile"` and `batchWriteAgentProfile:
    "update-profile"` to `AGENT_SKILL_COMMAND_NAMES`, and the two tool names to
    `AGENT_MCP_TOOL_NAMES`.
*   **File 38.** Add `"read-profile"` (`GET /agent/profile`) and `"update-profile"`
    (`POST /agent/profile/batch-write`, `body: true`) to the command map, following
    `read-settings` and `update-settings`.
*   **Files 39 to 42.** Run `corepack pnpm --filter @perennia/contract generate`. The diff shows
    only the additions listed under Agent surface › Contract diff.
*   **File 59.** Add `readAgentProfile` and `batchWriteAgentProfile` to the portable client, with
    the same method names as the generated client (file 40).
*   **File 60.** Add `read-profile` and `update-profile` examples next to the `read-settings` and
    `update-settings` examples.

#### Tests (files 43 to 53)

*   **File 43** (`js` job, against Postgres):
    *   read when empty, and `null` for an all-unset row;
    *   partial write: an absent field is kept and `null` clears; a list replaces the whole
        list;
    *   Health & limitations normalisation in both directions;
    *   a strict-schema 400 for an unknown field and for `birthYear: "1990"`;
    *   a hard reject returns 422 and writes nothing;
    *   a soft warning (birth year 1915) applies and returns the warning;
    *   a stored Equipment id the rules reject reads back as stored, and blocks a write of its
        section with a 422 naming `equipment`;
    *   re-sending the same fields adds no Batch and no nudge, leaves `updated_at` alone, and
        undo of the first Batch still applies;
    *   a write the database refuses returns 500, and the logged error holds no value;
    *   an idempotent replay returns `duplicate: true` and appends no Batch;
    *   newest-per-section read when two rows exist;
    *   undo, and undo of the whole Batch refused after an intervening change;
    *   redaction of the two free-text sections in `listAgentActivity`, with the other sections
        not redacted.
*   **File 44** (`js` job): push and pull of the entity, tenant isolation (a foreign id is
    dropped), a push with a value the domain rules would reject is still accepted, and a full
    re-sync snapshot includes the rows.
*   **File 45** (`sync` job): two devices editing different sections both survive (CUJ 9); two
    devices editing one section converge on the newer row (CUJ 5 shape).
*   **File 46:** add the two tool names to the expected list, and assert that
    `agent_list_activity` returns redacted values for a Health & limitations change.
*   **File 47:** assert that `sections` and `values` are scrubbed, that a real
    `DrizzleQueryError` holding a profile payload reaches the logger and Sentry with no query
    text or params, that `beforeSend` keeps `exception.values` with each message filtered and
    removes `request.data`, and, on the real SDK with a stubbed transport and a real HTTP
    request, that a 500 on `/agent/profile/batch-write` sends no request body.
*   **File 48:** assert that `user_profile_sections` is empty for the user after purge.
*   **File 49** (in-memory SQLite):
    *   save and watch; unset versus none; clear a field;
    *   a save of nothing on an empty section writes no row;
    *   hard errors throw; warnings do not block `saveSection`;
    *   Health & limitations normalisation;
    *   newest-per-section when two rows exist, including a pulled newer row;
    *   device undo restores a section, and is refused after an intervening change;
    *   portable archive round trip, merge-only;
    *   `ageAt` at the year boundary in local time.
*   **File 50:** the entity's pending changes push after `nutrition_goals` and are
    acknowledged; a pulled row is applied; a full re-sync tombstones a row missing from the
    snapshot.
*   **Files 51 and 52:** add the table to the erase-all guard (`_seedEveryDomain` and the
    expected tables) and to the archive's `tableNames` count.
*   **File 53:**
    *   each mode renders its exact disclosure line, once, under the title;
    *   the two free-text editors show their extra lines;
    *   every control meets the 48 dp target and has a semantics label;
    *   at 200% text scale nothing overflows and every control can be reached;
    *   a soft warning shows the confirm dialog, and **Save anyway** saves.

#### Docs (files 54 to 58)

*   **File 54.** Add User Profile and Training Goal as defined in Terms, replace the Equipment
    definition with the widened text in Terms, and add "Not the User Profile." to Record
    Profile.
*   **File 55.** In Sync, add `user_profile_sections` to the entity list, and the rule that the
    server runs no domain validation at push, with the reason given in Sync.
*   **File 56.** Add the disclosure line component: the `caption` type with the
    `text-secondary-light` / `text-secondary-dark` colour tokens, under the screen title.
*   **File 57.** Add **Profile** to the Screen map's Account & app line.
*   **File 58.** Added: "Profile under Account & app, with agent read and write
    (`read-profile`, `update-profile`). Upgrade a Self-Hosted Deployment before the app."

### PR 2: First-open onboarding

| # | File | Action | Why |
|---|---|---|---|
| 1 | `apps/mobile/lib/features/settings/repositories/settings_repository.dart` | Modify | `onboardingDone` device setting |
| 2 | `apps/mobile/lib/features/onboarding/repositories/onboarding_gate.dart` | Create | Gate provider |
| 3 | `apps/mobile/lib/features/onboarding/controllers/onboarding_controller.dart` | Create | Flow state and saves |
| 4 | `apps/mobile/lib/features/onboarding/widgets/onboarding_flow.dart` | Create | The three screens |
| 5 | `apps/mobile/lib/features/onboarding/widgets/onboarding_launcher.dart` | Create | Pushes the flow over Today |
| 6 | `apps/mobile/lib/app.dart` | Modify | Wrap the Today route |
| 7 | `apps/mobile/lib/l10n/app_en.arb` | Modify | Onboarding copy |
| 8 | `apps/mobile/lib/l10n/app_localizations*.dart` | Modify (generated) | `flutter gen-l10n` output |
| 9 | `apps/mobile/test/features/onboarding/onboarding_flow_test.dart` | Create | Flow, gate and accessibility tests |
| 10 | `apps/mobile/test/features/settings/app_settings_test.dart` | Modify | Default and parsing of the setting |
| 11 | `AGENTS.md` | Modify | Onboarding rule |
| 12 | `DESIGN.md` | Modify | Onboarding screen component |
| 13 | `CHANGELOG.md` | Modify | Release note |
| 14 | `docs/designs/user-profile.md` | Modify | Status to Current |
| 15 | `docs/designs/SITEMAP.md` | Modify | Status to Current |

**Verifies:** Verification Plan items V8 and V10.

*   **File 1.**
    *   Add `final bool onboardingDone` to `AppSettings` as a device-level, never-synced field,
        with a docstring saying why it is not synced (Onboarding gate).
    *   The constructor default and `AppSettings.defaults` are `true`, so
        `InMemorySettingsRepository` and every existing widget test skip onboarding.
    *   `FileSettingsRepository.load` reads `onboardingDone` from `settings.json`, and treats a
        missing file or a missing key as `false`, so a fresh install and an install from before
        this feature both see onboarding once.
    *   `SplitSettingsRepository` keeps it in the device store.
    *   Add `copyWith`, `toJson`, equality and `hashCode` entries, and
        `SettingsController.setOnboardingDone()`, following `setOnlineFoodLookups`.
*   **File 2.** `final onboardingGateProvider = FutureProvider<bool>(...)`, true when
    `onboardingDone` is false and `userProfile.hasAnySection()` is false. Tests override it.
*   **File 3.**
    *   States: `screen1`, `screen2`, `screen3`, `done`.
    *   `next()` saves the current screen (screen 1 follows the save order under Onboarding
        flow, through `SettingsController.setUnitSystem` and `setWeekStartDay`, then
        `userProfile.saveSection(aboutYou)`; screens 2 and 3 call `saveSection` once each, with
        one `batchId`). On screen 1 it then calls `setOnboardingDone()`.
    *   **Next** passes only the fields the user entered. A screen with nothing entered saves
        nothing.
    *   Soft warnings use the same confirm dialog as the Profile screen before saving.
    *   `skipThis()` saves nothing for the screen. On screen 1 it calls `setOnboardingDone()`.
    *   `skipAll()` calls `setOnboardingDone()` if it is not set, then goes to `done`.
    *   `back()` is available on screens 2 and 3.
    *   `signIn()` opens the existing sign-in screen (`sign_in_screen.dart`) and awaits its
        result. On success it calls `setOnboardingDone()` and goes to `done`, without waiting
        for a Sync Run. On cancel it stays on `screen1`.
*   **File 4.**
    *   The three screens, reusing the field widgets from PR 1's editors
        (`profile_section_editors.dart`), plus the existing units and week start controls.
    *   Every screen has **Skip all** in the app bar, and **Skip this** and **Next** at the
        bottom. Screen 3's **Next** reads **Done**.
    *   Screen 1 has the **Already use Perennia? Sign in** link.
    *   The disclosure line for the current mode sits in the footer.
    *   Nothing asks for an OS permission.
*   **File 5.** `OnboardingLauncher` wraps `HomeScreen`. On its first frame it reads
    `onboardingGateProvider.future`. If the result is true, it pushes `OnboardingFlow` as a
    full-screen route that the system back gesture does not close, and pops it on `done`. Today
    renders underneath from the first frame, so no spinner is shown.
*   **File 6.** The `HomeScreen.routeName` entry in `routes` builds
    `OnboardingLauncher(child: HomeScreen())`.
*   **Files 7 and 8.** The onboarding strings, verbatim:
    *   screen titles: "About you", "Training Goals and Experience", "Training setup";
    *   buttons: "Skip all", "Skip this", "Next", "Done", "Back";
    *   the sign-in link: "Already use Perennia? Sign in".

    Then run `flutter gen-l10n`.
*   **File 9** (against in-memory SQLite, with `onboardingDone` false):
    *   CUJ 1, CUJ 2 and CUJ 4;
    *   CUJ 3: kill and reopen on screen 1 before any tap (onboarding shows again) and on
        screen 2 (it does not);
    *   the gate is false when a section row exists, and false when `onboardingDone` is true;
    *   **Next** with nothing entered writes no section;
    *   undoing the About you Batch leaves `onboardingDone` set and the settings intact;
    *   sign-in success sets `onboardingDone` and reaches Today without a Sync Run; cancel
        returns to screen 1;
    *   accessibility: every control at least 48 dp with a semantics label, and at 200% text
        scale nothing overflows and every control can be reached.
*   **File 10.** A missing `settings.json`, and one without the key, load `onboardingDone:
    false`; `AppSettings.defaults` is `true`; the value round-trips.
*   **File 11.** Replace the "No onboarding wizards" bullet with the text given under Repository
    doc changes.
*   **File 12.** Add the onboarding screen component: **Skip all** in the app bar, the bottom
    action row (**Skip this**, **Next**), and the footer disclosure line.
*   **File 13.** Added: "Optional first-open onboarding, skippable from its first screen."
*   **Files 14 and 15.** Set this spec's Status, and its SITEMAP row, to Current.

### Verification Plan

*   **V1. Gate.** `pnpm ci:local mobile golden contract js sync release_version` passes for each
    PR. The `js` and `sync` jobs need Docker running.
*   **V2. Golden vectors.** PR 1 files 6 and 9 run the same m41 cases in Dart and TypeScript.
*   **V3. Repositories against in-memory SQLite.** PR 1 files 14, 49, 51 and 52.
*   **V4. Server integration.** PR 1 files 43, 44, 46, 47 and 48 (`js` job).
*   **V5. Sync simulation.** PR 1 file 45 (`sync` job) and file 50 (device).
*   **V6. Contract.** The `contract` job's drift check shows only the additions listed under
    Agent surface › Contract diff.
*   **V7. Accessibility.** PR 1 file 53.
*   **V8. Onboarding and kill-and-reopen.** PR 2 files 9 and 10. The logging path is unchanged,
    so the standing mid-workout kill-and-reopen scenario needs no new case.
*   **V9. Privacy pre-merge steps (PR 1).** The steps under Non-Functional Requirements ›
    Security & Privacy are done before the first hosted release that contains PR 1.
*   **V10. Manual checks before PR 2 merges.** On a release build on a device, each from a fresh
    install:
    1.  Tap **Skip all** on screen 1, then kill and reopen: Today opens with no onboarding.
    2.  Kill the app on screen 1 before tapping anything, then reopen: onboarding shows again.
    3.  Sign in from screen 1 against a staging account that has a filled User Profile: Today
        opens at once, and the Profile screen shows the account's values after the first Sync
        Run.
