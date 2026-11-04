# User Profile and First-Open Onboarding

*   **Author:** Leonardo Pinheiro
*   **Status:** Draft
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

It also adds three ways to fill the record:

1. **A Profile screen** under Account & app, where every section can be read and edited.
2. **A first-open onboarding** of at most three screens:
   - About you, with units and other general preferences.
   - Training Goals and Experience.
   - Training setup.

   It can be skipped from its first screen, and once dismissed or completed it does not come
   back, on this device or any other synced to the same account.
3. **Inline asks.** A feature that needs one missing field asks for that field once, where it
   is used, and never again after it is answered or dismissed. This spec supplies the synced
   record of dismissals and the rule. The first feature that asks builds the ask card.

Agents read and write the User Profile through REST and MCP, with the same rules as the app.
Every change is recorded in the Activity Log and can be undone. Nothing limits which agent reads
which field. Instead, each section states plainly who can read it.

The spec also replaces the AGENTS.md rule "No onboarding wizards, no sample data; the empty Home
Screen's CTA is the onboarding" with a rule that allows one optional onboarding that can be
skipped from its first screen. No sample data stays a rule.

## The Problem

Perennia holds nothing about the user as a person. It has no sex, age, height, goals, experience
or constraints. Three readers need some of this:

- **Lab results.** A separate lab-results spec shows a general reference range when a lab report
  prints none. Those ranges depend on sex and age. Without a place to store them, every result
  without a printed range is shown with no range at all, and a typical user cannot interpret the
  number.
- **Agents.** Agents connected to a Synced Mode account already create Workout Templates,
  Routines, Nutrition Goals and Protocols. An agent writing a training plan has to know the
  user's goals, experience, available equipment and time, and injuries. Today it has to ask the
  user each time, or guess. Some of this can be inferred from logged history, but that history
  says nothing about an injury, a goal or the equipment at home.
- **People, later.** A human-coaching feature may come later. It is not designed here, but the
  record and its disclosure copy must not assume the reader is always an AI agent.

The primary user is a hybrid athlete training for longevity. They are often
advanced in one discipline and new to another. Many of them take compounds that affect hormones.
They are also careful about what they share. This leads to three requirements:

- Every field is optional.
- The user can see who can read each field.
- Experience cannot be a single level for the whole person.

Why onboarding, and why now. The current AGENTS.md rule assumes the user installs the app on the
gym floor and wants to log a set immediately. The target user usually installs it at home. They
then spend time setting up Routines, Protocols and nutrition before their first Workout. A short
onboarding that can be skipped from its first screen asks for the core facts at the moment the
user is already setting up. The friction the old rule guarded against is handled by making
dismissal one tap and permanent.

Two existing mechanisms do not fit:

- **`UserSettings` cannot hold the profile.** It syncs as one row under last-writer-wins, and
  the agent settings write rebuilds it from its eight known fields. An agent settings write, or
  an older app build, would silently erase any profile fields stored on it.
- **Body Weight already has a home.** It is a Metric with history and a Trend. Weight changes
  every week; the facts in the User Profile change rarely. So weight stays a Metric, and
  onboarding saves a Body Weight reading rather than a User Profile field.

## Goals

1. **A User Profile record with six independent sections.** Each field can be:
   - *unset*: never answered;
   - *none*: answered as "nothing applies", for example "no limitations";
   - set to a value.

   Agents can tell these three states apart.
2. **Sections sync independently.**
   - Edits to two different sections on two offline devices both survive the next Sync Run.
   - An edit to the same section on two devices resolves by last-writer-wins, and the losing
     version can be recovered from the Activity Log.
   - An empty local section never overwrites a filled one from the server.
3. **A stable read contract for other specs.** The fields, their units, and which ones may be
   empty are fixed by this spec. Age is derived from birth year at a given date and never
   stored.
4. **Agent parity.**
   - One read operation and one partial batch-write operation, over REST and MCP, with the same
     validation as the app.
   - Absent means unchanged; explicit null means clear.
   - Every write is one Activity Log Batch, undoable from the app and through agent undo.
5. **Two-tier validation in one shared module.**
   - Hard rejects for impossible values: a birth year in the future, a non-positive height, text
     over the cap, an unknown list value.
   - Soft warnings for improbable values: an age over 100, a height outside a plausible range.
   - Agents receive the warnings and confirm them explicitly.
   - Golden vectors in Dart and TypeScript cover both tiers.
6. **A first-open onboarding.**
   - At most three screens, each with "Skip this" and "Skip all".
   - A "Sign in" link on screen 1 for users who already have an account.
   - Shown at most once per account once the device has synced.
   - It asks for no OS permission, imports nothing, creates no Routine and adds no sample data.
7. **Inline asks.**
   - A feature may ask once for one missing field, in context.
   - Answering or dismissing an ask is remembered across devices.
   - This spec owns the record of dismissals and the rules an ask must follow. The first
     consumer spec builds the ask card, and each consumer spec owns its copy and where the ask
     appears.
8. **Accurate disclosure** in every state:
   - Local-only Mode;
   - Synced Mode with no agent keys;
   - Synced Mode with agent keys.

   The copy names every reader: the service operator, connected agents, and later anything else
   connected to the account. It says that change history is kept for up to 180 days on the
   server.
9. **Health text is redacted from agent history.** Agent reads of the Activity Log show that
   Health & limitations or General Notes changed, and who changed them, but not the text.
10. **Lifecycle.**
    - Account deletion removes the User Profile.
    - Backup and restore include it, merge-only.
    - Logs and crash reports never contain its values.

## Non-Goals

- **Agent key scopes or per-field "hide from agents" settings.** Every connected agent can read
  every field. Scopes may come in a later spec.
- **Weight or body fat as User Profile fields.** Weight stays a Metric; body fat is not asked.
- **Nutrition targets computed from the User Profile.** The app is a logbook, not a
  coach: it records what the user planned and did, and leaves advice to the user and their
  agents. An in-app energy calculation would be a new golden-vectored analytics
  computation. Agents can already read the User Profile and write Nutrition Goals.
- **Any in-app use of Training Goals, Experience, Training setup or Health & limitations.** In
  this spec they exist for agents (and later coaches). The app does not change its suggestions
  based on them.
- **Medications in Health & limitations.** Compounds and Doses belong to Protocols. The Health
  copy points there instead of storing the same fact twice.
- **Onboarding beyond the user and general preferences.** No import from other apps, no first
  Routine, no Protocol setup, no tracker connection.
- **Extending the Equipment registry** with cardio or aquatic items. Anything not in the registry
  goes in General Notes.
- **Onboarding or profile analytics** of any kind, including completion or skip counts.
- **The hosted operator's legal obligations** for health information: privacy policy wording and
  regional law. This spec names them and does not solve them.
- **The lab-results behaviour itself.** For example, which range to show when sex is unset is
  specified there. This spec only supplies the fields.

## Open Questions

*   **Exact disclosure wording review.** The copy below is specified so the implementer has no
    choice to make, but the maintainer may want a privacy reviewer to read it before the
    implementation pull request merges. This does not block approval of the design.

## Critical User Journeys (CUJs)

### CUJ 1: New user skips everything

*   **Given**: A fresh install in Local-only Mode, with no authored data.
*   **When**: The user opens the app and taps **Skip all** on screen 1.
*   **Then**:
    *   The app writes one onboarding dismissal and no User Profile section.
    *   The user lands on Today.
    *   Onboarding never shows again on this install. Once the user signs in, it never shows on
        any device on that account.

### CUJ 2: New user fills About you and skips the rest

*   **Given**: A fresh install in Local-only Mode.
*   **When**: On screen 1 the user does the following, then taps **Skip this** on screens 2 and 3:
    1. picks Imperial units;
    2. sets sex to Female, birth year to 1990, height to 5 ft 6 in, and weight to 140 lb;
    3. taps **Next**.
*   **Then**:
    *   Screen 1 saves, in the order given under Onboarding flow, the unit-system setting, the
        About you section (height stored as 66 in) with the onboarding dismissal, and one Body
        Weight Metric Reading of 140 lb in a Body Weight Metric seeded in pounds.
    *   No Training Goals, Experience or Training setup section exists. All of them read as
        *unset*.
    *   The onboarding dismissal was written when the user left screen 1.

### CUJ 3: The app is killed mid-onboarding

*   **Given**: The user saved screen 1 and is on screen 2.
*   **When**: The app is killed and reopened.
*   **Then**:
    *   Onboarding does not show again, because the dismissal was written when the user left
        screen 1.
    *   The About you section is intact.
    *   If the app is killed on screen 1 before the user taps anything, onboarding shows again
        on reopen.

### CUJ 4: Existing user reinstalls and signs in from screen 1

*   **Given**:
    *   An account whose server holds a filled User Profile and an onboarding dismissal.
    *   A fresh install of the app.
*   **When**: The user taps **Already use Perennia? Sign in** on screen 1 and signs in.
*   **Then**:
    *   Onboarding closes without writing anything.
    *   After the first Sync Run, the pulled dismissal keeps onboarding from showing again.
    *   The Profile screen shows the account's User Profile.

### CUJ 5: Existing user fills onboarding on a second device, then signs in

*   **Given**:
    *   The account's About you on the server is: Male, 1988, 180 cm.
    *   On a fresh second device, the user fills only the sex field on screen 1 (Male) and
        finishes onboarding in Local-only Mode.
*   **When**: The user signs in, and the first Sync Run pulls the server's About you row.
*   **Then**:
    *   The local row was never synced, so the device fills its unset fields from the pulled row
        before pushing.
    *   Both copies end as Male, 1988, 180 cm.
    *   The account's birth year and height are not erased.

### CUJ 6: An agent writes, and the user undoes it

*   **Given**: A Synced Mode user with one agent key.
*   **When**: The agent calls `batchWriteAgentProfile` with:
    *   Training Goals: strength and longevity;
    *   Training setup: days per week 4.

    The user then undoes that change from the Activity feed.
*   **Then**:
    *   The write is one Batch with two section changes.
    *   Undo restores both sections to their prior state, on the device and on the server.
    *   If another change to the same section happened in between, undo of that section is
        refused with the existing "changed since" message.

### CUJ 7: An agent sends an improbable value

*   **Given**: An agent key.
*   **When**: The agent writes birth year 1915 without `confirm_warnings`.
*   **Then**:
    *   Nothing is written.
    *   The response has status `needs_confirmation` and a warning `birth_year.improbable_age`.
    *   Re-sending with `confirm_warnings: true` writes it.
    *   Writing birth year 2031 (a future year) is a hard reject, whatever `confirm_warnings`
        says.

### CUJ 8: Health text is cleared

*   **Given**: A Synced Mode user has a knee injury noted in Health & limitations.
*   **When**: The user clears the text and taps **None**.
*   **Then**:
    *   The section reads as *none*.
    *   The user's own Activity feed still shows the old text, because it is their own history.
    *   `GET /agent/activity` shows that Health & limitations changed and who changed it, but no
        text.
    *   The disclosure line on the section says history is kept for up to 180 days on the
        server.

### CUJ 9: Two devices edit different sections offline

*   **Given**: Phone A and Phone B are both synced and both offline.
*   **When**: A edits Training setup, and B edits General Notes. Both reconnect.
*   **Then**: Both edits survive, because they are different section rows.

### CUJ 10: An inline ask is dismissed on one device

*   **Given**: The lab-results spec defines an ask with key `lab_results.sex`.
*   **When**: The user dismisses it on Phone A.
*   **Then**: After sync, Phone B never shows that ask. The sex field is still unset, and the
    Profile screen can still set it.

### CUJ 11: A pre-release install updates

*   **Given**: An install from before this feature, with logged Workouts.
*   **When**: The app updates and opens.
*   **Then**: No onboarding shows and nothing is written. The Profile tile is available under
    Account & app.

### CUJ 12: Account deletion

*   **Given**: A Synced Mode user with a User Profile.
*   **When**: The account is deleted and purged.
*   **Then**: The server's User Profile section rows and prompt dismissal rows are deleted with
    the user row.

## Technical Plan (Architecture)

### Terms

These terms are new. They are added to CONTEXT.md in the implementation pull request.

| Term | Definition |
|---|---|
| **User Profile** | The optional, synced record of who the user is and what they train for. It has six sections: About you, Training Goals, Experience, Training setup, Health & limitations, and General Notes. It is distinct from Record Profile (a per-exercise headline-record choice). Every field may be unset. The app itself reads only About you; the rest exists for Agents. |
| **Training Goal** | One outcome the user trains for, chosen from a fixed list (for example longevity or strength). Distinct from Nutrition Goal, from a Metric's goal direction, and from Focus, which is the discipline a Workout is performed under. |
| **Profile Prompt** | A one-time request for User Profile information: the first-open onboarding, or an inline ask for one field. Once dismissed or completed, it is never shown again on any device on the account. |

The existing **Equipment** definition is widened. It covers the tool normally used for an
Exercise, and also the equipment the user has access to, as listed in Training setup. Both use
the same registry ids.

"Profile" alone is used only in UI copy (the tile, the screen title). Code, the contract and
sync use `user_profile` / `UserProfile`.

### Data model

There are two new synced entities. Neither touches `UserSettings`.

```text
user_profile_sections          one live row per section (newest wins)
  id            text  PK       random UUIDv7 (device) / random UUID (server, agent write)
  section       text           about_you | training_goals | experience |
                               training_setup | health_limitations | general_notes
  values_json   text           section values, shape below
  + standard sync columns: sync_device_id, sync_previously_synced, updated_at, deleted_at

user_profile_prompts           add-only; a live row means "this prompt is done"
  id            text  PK       random
  prompt_key    text           "onboarding" | "<feature>.<field>", e.g. "lab_results.sex"
  + standard sync columns
```

On the server, both tables carry `user_id` referencing `user.id` with `onDelete: cascade`. The
sync payloads are `{ section, values }` and `{ prompt_key }`.

**Why random ids and "newest per section".** In Local-only Mode, a device has no user id. The
server primary key is global, and a push whose id another user already owns is dropped. So a
fixed id like `profile:<section>:<userId>` cannot be created before sign-in. This is the same
constraint `UserSettings` and `NutritionGoals` already have. Their pattern is reused:

1. **Reads** take the live row with the greatest `updated_at` for each section. Ties are broken
   by `id`, matching `agent-nutrition-goals.ts`.
2. **Writes** update that row in place. A section row is created only when none exists.
3. A device that pulls a newer row for a section it already holds uses that row from then on.
   The older row stays in the table, unread, as Nutrition Goals rows do.

**Section values.** In every section, `null` means *unset*.

| Section | `values` shape | *none* |
|---|---|---|
| `about_you` | `sex`: `"female"` \| `"male"` \| null; `birth_year`: integer \| null; `height`: `{ value: number, unit: "cm" \| "in" }` \| null | not applicable |
| `training_goals` | `goals`: TrainingGoalId[] \| null | `[]` |
| `experience` | `levels`: `{ focus_id: string, level: "beginner" \| "intermediate" \| "advanced" }[]` \| null | `[]` |
| `training_setup` | `equipment`: EquipmentId[] \| null; `days_per_week`: integer \| null; `session_minutes`: integer \| null | `equipment: []` means no equipment beyond bodyweight |
| `health_limitations` | `text`: string \| null; `none`: boolean | `none: true` (requires `text: null`) |
| `general_notes` | `text`: string \| null | not applicable |

Rules for the values:

- **TrainingGoalId** is one of:
  - `longevity`;
  - `strength`;
  - `muscle_gain`;
  - `body_composition`;
  - `endurance_performance`;
  - `mobility`;
  - `general_fitness`.

  The list is unordered and has no duplicates.
- **Experience levels.** Each level has a one-line meaning shown in the UI:
  - beginner: under a year of regular training in this Focus;
  - intermediate: one to three years;
  - advanced: more than three years.

  `focus_id` is any Focus id, with no foreign key, following `Exercises.focusIds`. Starter
  Focuses are seeded with fixed ids, so they match across installs. An entry whose Focus is
  archived is kept, hidden in the UI, and returned to agents with `archived: true`.
- **EquipmentId** is an id from the `ExerciseEquipment.known` registry. Unknown ids are a hard
  reject.
- **Height** is stored as entered.
  - Metric entry stores centimetres.
  - Imperial entry of feet and inches stores the total in inches. For example, 5 ft 6 in is
    stored as 66 in.
  - Conversion happens on read only.
- **Age is never stored.** `ageAt(date)` is `date.year − birth_year`. It is accurate to ±1
  year, which is the precision a reference-range lookup needs.

**Section state and the screen.**
- A section with no row is unset.
- Each section on the Profile screen has a **None** choice where *none* applies. A user who
  selects None writes `[]` or `none: true`.
- Clearing a field writes `null`. If every field in a section is `null`, the row stays, with all
  fields unset. It is not deleted, because the user never deletes the record, only empties it.

### Sync

Both entities sync through the existing per-row path:
- They are added to `SYNC_PUSH_ENTITIES` and the pull list.
- Server pushes use row-level LWW on `updated_at`, like `nutrition_goals`.
- On the device they use the standard apply path.

Two rules are added:

1. **Unsynced rows fill unset fields from the server copy.**
   - When a device applies a pulled `user_profile_sections` row, it checks for its own live row
     for the same section with `sync_previously_synced = false` (never pushed).
   - If it finds one, it copies every field that is `null` locally and set remotely into its own
     row, keeps its own `updated_at`, and then pushes.
   - Fields the user set locally win. Fields they never answered take the account's value.
   - This applies only to never-synced rows. After the first push, edits are ordinary whole-row
     LWW, so an intentional clear on one device propagates.
   - The losing remote row stays in the Activity Log as usual.
2. **Prompt rows are a union.** A prompt counts as done if any live row with that `prompt_key`
   exists. Duplicate rows from two devices are harmless. Prompt rows are never edited or
   deleted by the app, so LWW never applies to them in practice.

**Rollout.** The server ships first. A newer app talking to a server without these entities must
not lose data or stall other sync. Before pushing either entity, the device checks the server's
supported-entity list. Until the server supports both entities, they stay pending on the device
and other entities sync normally. The Detailed Implementation Plan names the mechanism.

### Onboarding gate

Onboarding shows at app start, after the database opens and before the Today root, when all of
these hold:

1. No live `user_profile_prompts` row has `prompt_key = "onboarding"`.
2. No live `user_profile_sections` row exists.
3. The install holds no authored data. That means no live row in any of:
   - Workouts;
   - Workout Templates;
   - Routines;
   - Food Entries;
   - Protocols;
   - Metric Readings with manual provenance.

Condition 3 covers pre-release installs without writing a migration row: an install with
history is treated as already onboarded.

The gate is checked at each app start. It is not checked again while the app runs, with one
exception: after the first Sync Run that follows a sign-in started from onboarding (see below).

### Onboarding flow

```text
 app start ──gate true──► [1 About you + preferences] ──► [2 Training Goals + Experience] ──► [3 Training setup] ──► Today
                │                 │  Next = save screen 1 Batch, write dismissal
                │                 │  Skip this = write dismissal, go to 2
                │                 │  Skip all = write dismissal, go to Today
                │                 │  "Already use Perennia? Sign in" = open sign-in, write nothing
                └─gate false──► Today
```

- **Dismissal.** The onboarding dismissal row is written the first time the user leaves screen 1
  by **Next**, **Skip this** or **Skip all**. From then on, killing the app never brings
  onboarding back.
- **Saving.** Each screen saves on **Next** as one Activity Log Batch. **Skip this** writes
  nothing for that screen. **Skip all** on screens 2 and 3 goes to Today, keeping what was
  saved.
- **Back.** Screens 2 and 3 have a back arrow. Going back to a saved screen and saving again
  writes another Batch.
- **Sign in from screen 1.**
  - It opens the existing sign-in flow.
  - On success, the device runs its first Sync Run and then checks the gate again.
  - If the gate is still true, because the account is empty, onboarding reopens at screen 1.
  - If sign-in is cancelled, the user returns to screen 1.
- **Screen 1 save order.**
  1. Save the unit system and week start day through the existing `SettingsController`.
  2. Make sure the Body Weight Metric exists, seeded in that unit system's weight unit.
  3. Write the About you section.
  4. If a weight was entered, create the Body Weight reading.

  These are up to three Activity Log Batches, because the existing settings and Metric write
  paths each open their own:
  - the settings change;
  - the About you section with the onboarding dismissal;
  - the Body Weight reading.

  Each can be undone on its own from the Activity feed. Joining them would mean changing
  existing write APIs that no other feature needs changed. If Body Weight is archived, or no
  Metric with that name exists and seeding fails, the weight field is hidden.
- **What onboarding never does.** It asks for no OS permission, adds no sample data, imports
  nothing and creates no Routine.

Screen contents:

| Screen | Fields |
|---|---|
| 1 About you | Units (Metric / Imperial), week start day, sex (Female / Male / Not set), birth year, height, weight |
| 2 Training Goals + Experience | Training Goal chips (multi-select); for each active Focus, a level selector that defaults to unset |
| 3 Training setup | Equipment chips from the registry, days per week (1–7), usual session length in minutes |

Health & limitations and General Notes are not in onboarding. They appear only on the Profile
screen.

### Profile screen

The Profile screen opens from a **Profile** tile in the Account & app sheet, between account
status and Settings. It lists the six sections as cards. Each card shows its values or "Not
set", and tapping it opens an editor sheet. Each section card carries the disclosure line for
the current state. The Health & limitations and General Notes editors show a character counter
against their cap.

### Disclosure copy

There is one line per state, shown on every section card and in onboarding's footer.
`{server}` is "Perennia's servers" for the Official Service, or the host name for a Self-Hosted
Deployment.

| State | Copy |
|---|---|
| Local-only Mode | "Stored only on this phone. If you sign in, it syncs to your account, where the server's operator and any agent you connect can read it." |
| Synced, no agent keys | "Synced to {server}. The server's operator can read it, and so can any agent you connect. Past versions are kept for up to 180 days." |
| Synced, with agent keys | "Synced to {server}. The server's operator and your connected agents can read it. Past versions are kept for up to 180 days." |

Two more lines appear on specific sections:

- **Health & limitations and General Notes** add: "Agents see only the current text, not past
  versions."
- **Health & limitations** adds: "Medications and supplements belong in Protocols."

The copy says "the server's operator" rather than naming a company. That stays true for
self-hosters, and for a future coach feature. It also matches ARCHITECTURE.md (Sync):
the server stores and reads synced rows, and nothing is end-to-end encrypted.

### Inline asks

This spec ships the record and the rules. It does not ship an ask card, because nothing in
this spec would show one. The first consumer spec (lab results) builds the card with its first
placement, on this API:

- **Device API.**
  - `UserProfilePromptRepository.isDone(promptKey)` returns a stream.
  - `UserProfilePromptRepository.markDone(promptKey)` writes the row.
  - A consumer supplies a `prompt_key` (`<feature>.<field>`), the field, and the copy.
- **Rules every ask follows.**
  - It shows only when the field is unset and the prompt is not done.
  - Saving writes the field as a User Profile change through `saveSection`. No prompt row is
    needed, because the field is no longer unset.
  - Dismissing it calls `markDone`.

What is forbidden anywhere in the app:
- badges;
- completion percentages;
- "complete your profile" banners;
- a repeat of a done prompt.

Prompt rows are presentation state and are not part of the agent surface. Agents can read the
User Profile fields themselves, which is what a prompt guards.

### Agent surface

The REST surface is generated from the route definitions. The MCP tools are registered by hand.

| | REST | MCP tool |
|---|---|---|
| Read | `GET /agent/profile` (`readAgentProfile`) | `agent_read_profile` |
| Write | `POST /agent/profile/batch-write` (`batchWriteAgentProfile`) | `agent_batch_write_profile` |

- **Read** returns every section as `{ values, updated_at }`, or `null` when unset. Experience
  entries include the Focus name and `archived`.
- **Write body:** `{ batch_id, sections: { <section>?: { <field>?: value | null } }, confirm_warnings?: boolean }`.
  - An absent section or field is unchanged.
  - `null` clears the field.
  - A list value replaces the whole list.
  - The server merges the given fields into the current values of each named section and
    writes the whole section row. That is one Activity Log Batch, made idempotent by `batch_id`,
    as the settings write is.
- **Validation.** It runs through the shared module before anything is written.
  - Any hard reject returns the existing validation-error response, and nothing is written.
  - If there are soft warnings and `confirm_warnings` is not `true`, the response is
    `{ status: "needs_confirmation", warnings: [{ code, field, message }] }` and nothing is
    written.
  - Otherwise the response is `{ status: "applied", batch_id, sections: [...], warnings: [...] }`.
- **Contract diff:** two new operations, the section and write schemas, and the
  `needs_confirmation` status. No existing operation changes.
- **Agent undo.** `user_profile_sections` is added to the undoable-entity registry, so undo
  through the agent surface works as for other entities.
- **Activity redaction.** In `GET /agent/activity`, any change to a `user_profile_sections` row
  whose section is `health_limitations` or `general_notes` has its before and after `values`
  replaced with `{ "redacted": true }`. The entity, section, actor and time are kept. The user's
  own feed on the device is not redacted.

### Validation

There is one module per language, golden-vectored. `reference_year` is an input to every vector,
so results do not depend on the clock.

| Field | Hard reject | Soft warning (code) |
|---|---|---|
| `birth_year` | > reference_year, or < reference_year − 130 | age < 13 or > 100 (`birth_year.improbable_age`) |
| `height` | value ≤ 0, or > 300 cm (118 in), or unknown unit | < 120 cm or > 220 cm (`height.improbable`) |
| `days_per_week` | < 1 or > 7 | none |
| `session_minutes` | < 1 or > 600 | > 240 (`session_minutes.improbable`) |
| `goals`, `equipment`, `levels` | unknown id, duplicate, or invalid level | none |
| `health_limitations.text` | > 1,000 UTF-16 code units, or `none: true` with non-null text | none |
| `general_notes.text` | > 2,000 UTF-16 code units | none |
| `sex` | value outside the set | none |

The UI shows soft warnings inline and saves on the second tap, which is the existing UI pattern
for soft warnings.

### Read contract for other specs

Other features read the User Profile only through `UserProfileRepository.watch()`. It returns a
`UserProfile` value with:
- a typed getter per field, each nullable;
- `ageAt(DateTime)`, which returns an integer or null.

The lab-results spec uses `sex` and `ageAt(sampleDate)`. This spec guarantees these names,
types and nullability.

### Lifecycle

- **Account deletion.** Both server tables cascade from `user`.
- **Backup and restore.** Both tables are included in the portable archive. Restore is
  merge-only: a section row is imported if its id is new, and LWW by `updated_at` applies if it
  exists. Prompt rows are imported if new.
- **Logs and crash reports.** The observability scrub lists gain these keys:
  - `sex`, `birth_year`, `height`;
  - `goals`, `levels`, `equipment`;
  - `days_per_week`, `session_minutes`;
  - `text`, `values`, `sections`.

  Logs record only ids and section names.

### Invariants touched

| Invariant | How it is preserved |
|---|---|
| Sets self-describing / values as entered | Height is stored with the unit it was entered in, and converted on read. |
| Derived analytics never stored | Age is computed from birth year on read. Nothing about the User Profile is derived and stored. |
| Delete = archive; no cascading deletes | The user only clears fields. A section row is never deleted by the app. A Focus archived after an Experience entry keeps the entry. The only cascade is account purge, which is the existing deletion path. |
| Restore is merge-only | The new tables join the existing merge-only archive import. |
| Local writes never block on the network | All writes are local Drift writes. Onboarding never waits for sync, except after a sign-in the user chose. |
| Silent LWW with recoverable losers | Per-row LWW, with losers in the Activity Log. The fill rule for never-synced rows only adds values, never overwrites one, and shows no dialog. |
| One shared two-tier validation module | The new rules live in the shared module, are golden-vectored, and reach agents as `needs_confirmation`. |
| No behavioral analytics | Nothing about onboarding or prompts is counted or sent. |

### Repository doc changes

- **AGENTS.md.** The bullet "No onboarding wizards, no sample data; the empty Home Screen's CTA
  is the onboarding." is replaced with:

  > Onboarding is optional: one first-open flow of at most three screens, skippable from its
  > first screen, never shown again once dismissed or completed, and never with sample data.
  > The empty Home Screen's CTA is still how a new user starts logging.

  The Screen map gains **Profile** under Account & app.
- **CONTEXT.md.** The three new terms, the wider Equipment definition, and a pointer from Record
  Profile ("not the User Profile").
- **ARCHITECTURE.md (Sync).** The two entities and the fill rule for never-synced rows.
- **DESIGN.md.** Components for the onboarding screen and the disclosure line.

### Staging

The work is one spec, in two implementation pull requests:

1. **Stage 1.**
   - The record, sync, validation and golden vectors.
   - The Profile screen and its disclosure copy.
   - The agent surface, undo and redaction.
   - The Profile Prompt record, backup and observability.
   - The CONTEXT.md, ARCHITECTURE.md and DESIGN.md changes.
2. **Stage 2.** Onboarding, the gate and the AGENTS.md rule change.

## Alternatives Considered

### Storage and sync

#### Alternative A: Add the profile fields to `UserSettings`

*   **Pros**:
    *   No new table or sync entity.
    *   The agent settings surface already exists.
*   **Cons**:
    *   `UserSettings` syncs as one opaque row under whole-row LWW. The agent settings write
        rebuilds that row from its eight known fields, so an agent settings write, or an older
        app build, would silently erase the profile fields.
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
    *   Device undo refuses once the row has changed since the change being undone. With one
        row, any later edit to any section blocks undo of an agent's write.
*   **Reason for Rejection**: It breaks the promise that independent sections sync and undo
    independently (CUJ 6, CUJ 9).

#### Alternative C: One row per field or list item, set-merged

*   **Pros**:
    *   Per-field LWW and per-field undo.
    *   No concurrent edit is ever lost.
*   **Cons**:
    *   Many more rows.
    *   Every read has to assemble the record from keyed rows.
    *   List membership needs its own add and remove rules, in both languages.
*   **Reason for Rejection**: The record is edited rarely, usually by one person on one device.
    Per-section conflict handling is enough, and the extra machinery would buy little.

#### Alternative D: Fixed ids per section (`profile:<section>:<userId>`)

*   **Pros**:
    *   Two devices always write the same row, so there is no "newest per section" read rule.
*   **Cons**:
    *   A Local-only device has no user id, so it cannot create the id before sign-in.
    *   Re-keying rows at sign-in would be new and error-prone.
*   **Reason for Rejection**: It cannot be built for the offline-first default. Random ids with
    "newest per section" follow the existing Nutrition Goals pattern.

### Privacy

#### Alternative E: Per-field "share with agents" toggles, or agent key scopes

*   **Pros**:
    *   A real access control, not only disclosure.
*   **Cons**:
    *   It is the first place agents would see less than the app, which cuts against agent
        parity.
    *   Every agent read and undo path would need to respect it.
    *   Users would need to understand it.
*   **Reason for Rejection**: The maintainer chose disclosure only for now. Scopes stay possible
    later without changing this record.

#### Alternative F: An "Advanced" tab for sensitive fields

*   **Pros**:
    *   Keeps the main screen short.
*   **Cons**:
    *   Where a field sits on screen does not change who can read it. Presenting it as a privacy
        measure would mislead users.
*   **Reason for Rejection**: Not a privacy control. Sensitive sections instead get their own
    disclosure lines, and Health & limitations and General Notes are kept out of onboarding.

#### Alternative G: Leave health history visible to agents

*   **Pros**:
    *   No special case in the activity read.
*   **Cons**:
    *   Text the user cleared from Health & limitations would stay readable by every connected
        agent for 180 days.
*   **Reason for Rejection**: Clearing a field would not do what the user expects. Redaction of
    the two free-text sections costs one rule in one read path.

#### Alternative H: Purge cleared health text from the Activity Log

*   **Pros**:
    *   Cleared text is truly gone.
*   **Cons**:
    *   The Activity Log is append-only, and it is how sync losers are recovered and undo works.
*   **Reason for Rejection**: It breaks the recoverable-loser invariant. Redaction plus a stated
    retention period is the trade-off chosen instead.

### Fields

#### Alternative I: Free text for Training Goals and Experience

*   **Pros**:
    *   Agents read prose well.
    *   No list to maintain.
*   **Cons**:
    *   No validation, so the record would drift.
    *   Agents get no stable values to branch on.
    *   It invites health detail into fields not labelled for it.
*   **Reason for Rejection**: Fixed lists are cheap here, and Experience has to be keyed by
    Focus anyway. Free text is kept where structure would mislead: Health & limitations and
    General Notes.

#### Alternative J: A fixed list for Health & limitations

*   **Pros**:
    *   Structured and filterable.
*   **Cons**:
    *   Injuries and conditions vary too widely for a list.
    *   A medical-sounding list invites the app to look like it gives medical advice.
    *   It would overlap with Protocols.
*   **Reason for Rejection**: Capped free text, with an explicit None, says what the user means
    with the least surface.

#### Alternative K: One experience level for the whole person

*   **Pros**:
    *   One question.
*   **Cons**:
    *   The primary user is often advanced in one discipline and a beginner in another. An agent
        given one level plans one of those wrong.
*   **Reason for Rejection**: The level is set per Focus instead, reusing an existing term.

#### Alternative L: Weight as a User Profile field

*   **Pros**:
    *   One place for "about you".
*   **Cons**:
    *   It duplicates the Body Weight Metric, which has history and a Trend.
    *   Weight changes weekly, so a profile field would go stale.
*   **Reason for Rejection**: Onboarding saves a Body Weight reading instead.

#### Alternative M: Full date of birth

*   **Pros**:
    *   Exact age.
*   **Cons**:
    *   More identifying, and every connected agent can read it.
    *   Reference ranges change by age band, so the extra precision is unused.
*   **Reason for Rejection**: Collect the minimum. Birth year gives age to ±1 year.

#### Alternative N: A third value for sex

*   **Pros**:
    *   More inclusive wording.
*   **Cons**:
    *   The field exists to choose a default reference range. A third value needs the lab spec
        to say which range it shows, and no published default range exists for it.
*   **Reason for Rejection**: The field is labelled for its purpose ("Sex used for default
    reference ranges"), and Not set is always available. The lab spec defines what Not set
    shows.

#### Alternative O: Store height in canonical centimetres

*   **Pros**:
    *   One unit on read.
*   **Cons**:
    *   Imperial entries round-trip with rounding.
    *   It departs from the project's "stored as entered" rule.
*   **Reason for Rejection**: Store as entered, convert on read.

#### Alternative P: Extend the Equipment registry with cardio and aquatic items now

*   **Pros**:
    *   Better coverage for hybrid athletes: treadmill, rower, bike trainer, pool.
*   **Cons**:
    *   It changes a registry that exercises also use. That is out of scope for a profile
        spec.
*   **Reason for Rejection**: Deferred. General Notes covers anything missing in the meantime.

### Onboarding

#### Alternative Q: Keep the AGENTS.md rule; no onboarding at all

*   **Pros**:
    *   No first-open friction.
    *   Inline asks alone already serve the lab spec.
*   **Cons**:
    *   Agents, the main reader of Training Goals, Experience and Training setup, would get
        values only from users who find the Profile screen on their own.
    *   The target user sets up at home before training, when a short flow costs little.
*   **Reason for Rejection**: The maintainer chose to change the rule. One-tap permanent
    dismissal keeps the friction the rule guarded against low.

#### Alternative R: Show onboarding only after sign-in

*   **Pros**:
    *   It knows the account state, so onboarding never shows twice.
*   **Cons**:
    *   Local-only users, the default, would never see it.
*   **Reason for Rejection**: Offline-first is the default. A sign-in link on screen 1 handles
    users who already have an account.

#### Alternative S: Wait for the first pull before deciding

*   **Pros**:
    *   Exact gate.
*   **Cons**:
    *   A fresh install has no credentials, so there is nothing to pull.
    *   Any wait puts a spinner on first open.
*   **Reason for Rejection**: Cannot apply to a fresh install. Instead, the gate is checked
    again after the first Sync Run that follows a sign-in started from onboarding.

#### Alternative T: Device-only dismissals in `settings.json`

*   **Pros**:
    *   No new synced entity.
*   **Cons**:
    *   Each device asks again. That breaks "if dismissed, we don't ask again".
*   **Reason for Rejection**: Prompt rows sync as a union.

#### Alternative U: A one-time migration that marks existing installs as onboarded

*   **Pros**:
    *   An explicit record.
*   **Cons**:
    *   Every existing device would write and push an Activity Log entry on upgrade.
*   **Reason for Rejection**: The gate's authored-data condition gives the same result without
    writing.

### Scope and rollout

#### Alternative V: Separate specs for the record, onboarding and the agent surface

*   **Pros**:
    *   Smaller documents.
*   **Cons**:
    *   Agent parity forbids an app capability without its agent operation.
    *   Onboarding's gate depends on the sync rules for the record.
    *   Splitting them leaves each spec unable to state its own invariants.
*   **Reason for Rejection**: One spec, built in two stages.

#### Alternative W: Nutrition targets computed from the User Profile

*   **Pros**:
    *   Users get suggested energy and protein targets.
*   **Cons**:
    *   It is a new golden-vectored analytics computation.
    *   It moves the app from a logbook towards a coach.
    *   Agents can already read the User Profile and write Nutrition Goals.
*   **Reason for Rejection**: Out of scope.

#### Alternative X: Ship the server first and rely on that alone

*   **Pros**:
    *   It is what earlier new entities did. No new mechanism.
*   **Cons**:
    *   A newer app pushing to a Self-Hosted Deployment that has not been upgraded fails the
        whole push, so all sync stops, not just the User Profile.
*   **Reason for Rejection**: Self-hosting is a supported mode. The server ships first, and the
    app also holds back entities the server does not list. The mechanism is in the Detailed
    Implementation Plan.

--------------------------------------------------------------------------------

## Non-Functional Requirements

*   **Security & Privacy**:
    *   The User Profile holds health information.
    *   Every reader is named in the disclosure copy, and agent history redacts the two
        free-text sections.
    *   Logs and crash reports never contain values.
    *   The hosted operator's privacy policy and regional obligations for health information
        are outside this spec. The implementation pull request must not merge to a hosted
        release until the maintainer confirms the privacy policy covers the User Profile.
*   **Performance & Latency**:
    *   Every write is a local Drift write, confirmed within one frame. The onboarding gate
        reads three small queries at start-up. It adds no network call and no spinner.
    *   A full agent read is at most about 3,500 characters, mostly the two capped text fields.
        That keeps it inside one agent request under the default rate limit.
*   **Rollout & Rollback**:
    *   The server ships first.
    *   The app holds back pushes of the two entities until the server lists them.
    *   The app cannot be downgraded in place. App stores do not allow it, and Drift refuses to
        open a newer schema. So rolling the app back means shipping a fix release on top of the
        additive schema-65 migration.
    *   Rolling the server back leaves the device rows pending.

--------------------------------------------------------------------------------

### Additional Resources

*   [docs/designs/protocol-schedules-and-reminders.md](protocol-schedules-and-reminders.md) sets
    the rule that no OS permission is requested outside its feature.
*   Code patterns reused:
    *   `apps/server/src/agent-settings.ts` (agent read and write);
    *   `apps/server/src/agent-nutrition-goals.ts` (newest live row per key);
    *   `UNDOABLE_ENTITY_REGISTRY` in `apps/server/src/agent-activity.ts`.

### Future Improvements

*   **Agent key scopes**, for example to exclude Health & limitations from a key. This record
    needs no change to support them.
*   **Equipment registry coverage** for cardio and aquatic items.
*   **In-app use of Training Goals and Experience**, for example ordering suggestions. Each such
    use would need its own spec.
*   **A human-coaching reader.** The disclosure copy already says "the server's operator and
    your connected agents". A coach would be added to the third state's copy.

--------------------------------------------------------------------------------

## Detailed Implementation Plan

There are two stages, in two implementation pull requests.

- **Stage 1:** files 1–36.
- **Stage 2:** files 37–45.

Every change that a user, agent or self-hoster can see adds a `CHANGELOG.md` line under
`## [Unreleased]`, `Added`. Both stages are minor-bump changes.

### Stage 1: record, sync, validation, Profile screen, agent surface, inline asks

#### Shared validation and golden vectors

**1. `packages/golden-vectors/vectors/m38-user-profile-validation.json` (Create)**

*   **Type / Scope**: Golden vectors.
*   **Proposed Changes**:
    *   Each case has `{ input: { reference_year, section, values }, expected: { errors: [codes], warnings: [codes] } }`.
    *   Cover every row of the validation table in the Technical Plan, at each boundary, both
        sides:
        *   birth year: `reference_year`, `reference_year + 1`, `reference_year − 130`,
            `reference_year − 131`, ages 12, 13, 100 and 101;
        *   height: 0, 119.9 cm, 120 cm, 220 cm, 220.1 cm, 300 cm, 300.1 cm, and 118 in / 118.1
            in;
        *   days per week: 0, 1, 7, 8;
        *   session minutes: 0, 1, 240, 241, 600, 601;
        *   text: 1,000 and 1,001 UTF-16 units, including a case with an astral-plane character
            that counts as 2;
        *   `none: true` with text;
        *   an unknown goal, equipment id and level;
        *   duplicates;
        *   an unknown sex.
    *   Error codes:
        *   `birth_year.future`, `birth_year.too_old`;
        *   `height.non_positive`, `height.too_tall`, `height.unit`;
        *   `days_per_week.range`, `session_minutes.range`;
        *   `text.too_long`, `health.none_with_text`;
        *   `goals.unknown`, `goals.duplicate`;
        *   `equipment.unknown`, `equipment.duplicate`;
        *   `levels.unknown_level`, `levels.duplicate_focus`;
        *   `sex.unknown`.
    *   Warning codes as in the Technical Plan.

**2. `packages/golden-vectors/vectors/m38-user-profile-validation.schema.json` (Create)**

*   **Type / Scope**: JSON Schema for file 1, following the existing `*.schema.json` files.
*   **Proposed Changes**: Defines the case shape above.

**3. `apps/mobile/lib/domain/profile/user_profile.dart` (Create)**

*   **Type / Scope**: Dart domain types.
*   **Proposed Changes**:
    *   `enum UserProfileSection { aboutYou, trainingGoals, experience, trainingSetup, healthLimitations, generalNotes }`,
        with wire names as in the Technical Plan.
    *   `enum TrainingGoalId` and `enum ExperienceLevel`.
    *   `ProfileSex { female, male }`.
    *   `ProfileHeight { double value; HeightUnit unit /* cm | inch */ }`.
    *   One immutable value class per section, with nullable fields and `toJson` / `fromJson` in
        the wire shape.
    *   `UserProfile`, holding the six optional sections. It has typed getters (`sex`,
        `birthYear`, `height`, `goals`, `experienceLevels`, `equipment`, `daysPerWeek`,
        `sessionMinutes`, `healthText`, `healthNone`, `generalNotesText`) and
        `int? ageAt(DateTime date)`, which is `date.year − birthYear`.

**4. `apps/mobile/lib/domain/profile/user_profile_validation.dart` (Create)**

*   **Type / Scope**: Dart validation, the shared two-tier module.
*   **Proposed Changes**:
    *   `ProfileValidationResult validateUserProfileSection(UserProfileSection section, Map<String, Object?> values, {required int referenceYear})`.
        It returns `errors` and `warnings` as lists of `{code, field}`.
    *   Limits are constants in `userProfileValidationLimits`, following `settings_validation.dart`.
    *   Equipment ids are checked against `ExerciseEquipment.known`.

**5. `apps/server/src/user-profile-validation.ts` (Create)**

*   **Type / Scope**: TypeScript validation.
*   **Proposed Changes**:
    *   The same function and codes as file 4: `validateUserProfileSection(section, values, { referenceYear })`.
    *   `USER_PROFILE_VALIDATION_LIMITS`.
    *   `PROFILE_EQUIPMENT_IDS`, a TypeScript copy of the `ExerciseEquipment.known` ids.
    *   `TRAINING_GOAL_IDS` and `EXPERIENCE_LEVELS`.

**6. `apps/server/test/user-profile-validation.golden.test.mjs` (Create)** and
**7. `apps/mobile/test/domain/user_profile_validation_test.dart` (Create)**

*   **Type / Scope**: Golden-vector runners.
*   **Proposed Changes**:
    *   Both run every case in file 1 and assert equal codes.
    *   The Dart test also asserts that `ExerciseEquipment.known` ids equal the JSON list
        `equipment_ids` embedded in file 1. Add that list to the file, so the TypeScript copy
        cannot drift.

**8. `apps/mobile/test/domain/golden_vector_ownership_test.dart` (Modify)**

*   **Type / Scope**: Test registry.
*   **Proposed Changes**: Register `m38-user-profile-validation.json` and its owners.

#### Device schema and repositories

**9. `apps/mobile/lib/data/local/app_database.dart` (Modify)**

*   **Type / Scope**: Drift schema, v64 → v65.
*   **Proposed Changes**:
    *   Add the `UserProfileSections` table: `id`, `section`, `valuesJson`, plus the standard
        sync columns.
    *   Add the `UserProfilePrompts` table: `id`, `promptKey`, plus the standard sync columns.
    *   Add both to `tableNames`.
    *   `schemaVersion` becomes 65. The migration from 64 creates both tables, and writes no
        rows.
    *   Docstrings explain:
        *   why the profile is not on `UserSettings`;
        *   the newest-per-section read rule;
        *   that prompt rows are add-only.

**10. `apps/mobile/drift_schemas/app_database/drift_schema_v65.json` (Create)** and
**11. `apps/mobile/test/generated_migrations/app_database/` (Modify)**

*   **Type / Scope**: Generated schema dump and migration test.
*   **Proposed Changes**: Generated by the existing drift schema tooling. Add a v64 → v65 step
    test that a populated v64 database upgrades with no data change.

**12. `apps/mobile/lib/data/repositories/user_profile_repository.dart` (Create, `part of` `training_repositories.dart`)**

*   **Type / Scope**: Repository. It is the only layer that touches these tables.
*   **Proposed Changes**:
    *   `Stream<UserProfile> watch()` reads the newest live row per section.
    *   `Future<void> saveSection(UserProfileSection section, Map<String, Object?> values, {String? batchId, bool confirmWarnings = false})`:
        1. Validates through file 4. Hard errors throw `ProfileValidationException`. Warnings
           without `confirmWarnings` throw `ProfileNeedsConfirmation`.
        2. Updates the newest row in place, or creates one with a UUIDv7.
        3. Appends one Activity Log change.

        A `null` field value clears that field; there is no separate clear method.
    *   `applySyncImage` implements the unsynced-fill rule. When a pulled row arrives for a
        section whose newest local row has `syncPreviouslySynced == false`, the device copies
        the remote non-null fields into local null fields, keeps the local `updatedAt`, and
        marks the row pending. Otherwise it applies standard LWW.

**13. `apps/mobile/lib/data/repositories/user_profile_prompt_repository.dart` (Create, `part of` `training_repositories.dart`)**

*   **Type / Scope**: Repository.
*   **Proposed Changes**:
    *   `Stream<bool> isDone(String promptKey)` is true when any live row has the key.
    *   `Future<void> markDone(String promptKey, {String? batchId})` inserts a row only if none
        exists locally. It never updates or deletes.
    *   `applySyncImage` inserts the pulled row if it is new.
    *   `promptKey` is validated against `^[a-z_]+(\.[a-z_]+)?$`.

**14. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)**

*   **Type / Scope**: Repository hub.
*   **Proposed Changes**:
    *   Add the two `part` directives and expose `userProfile` and `userProfilePrompts`.
    *   Add both entities to `_readImageFor` and `_writeImageFor`, so device undo restores a
        section row from its before-image. Prompt rows are excluded from undo, because they
        are presentation state.
    *   Add the tables to the erase-all-data path.

**15. `apps/mobile/lib/features/sync/repositories/sync_repository.dart` (Modify)**

*   **Type / Scope**: Sync client.
*   **Proposed Changes**:
    *   Register the loaders and apply paths for `user_profile_sections` and
        `user_profile_prompts`.
    *   **Entity gating.** Keep `serverPushEntities`, the last `pushEntities` list seen in a
        pull response. It is stored in memory and persisted in the sync state the repository
        already keeps.
    *   Define `gatedEntities = {user_profile_sections, user_profile_prompts}`.
    *   When building a push, leave out any pending change whose entity is in `gatedEntities`
        and not in `serverPushEntities`. Those changes stay pending. Other entities push as
        normal.
    *   A server that sends no `pushEntities` (an older server) gates both entities.
    *   Docstring: this is the rollout guard from the spec. Future new entities may be added to
        `gatedEntities`.

**16. `apps/mobile/lib/features/activity/repositories/activity_feed_repository.dart` (Modify)**

*   **Type / Scope**: Activity feed labels.
*   **Proposed Changes**: Labels for section changes, such as "Profile · Training setup
    updated". Prompt rows get no feed line.

**17. `apps/mobile/lib/data/repositories/portable_archive_repository.dart` (Modify)**

*   **Type / Scope**: Backup and restore.
*   **Proposed Changes**:
    *   Export both tables.
    *   Import merge-only:
        *   a section row is inserted if its id is new, otherwise LWW by `updatedAt`;
        *   a prompt row is inserted if new.

#### Profile screen and inline asks (device UI)

**18. `apps/mobile/lib/features/profile/controllers/profile_controller.dart` (Create)**

*   **Type / Scope**: Riverpod controller.
*   **Proposed Changes**:
    *   Watches `userProfile.watch()`, the sync mode, the server host name and the agent key
        count from `AgentApiKeyRepository`.
    *   Exposes `ProfileDisclosureState { localOnly, syncedNoKeys, syncedWithKeys }` and
        `serverLabel`.
    *   Exposes the save and clear actions, mapping `ProfileNeedsConfirmation` to an inline
        warning that saves on the second tap.

**19. `apps/mobile/lib/features/profile/widgets/profile_screen.dart` (Create)**

*   **Type / Scope**: Screen.
*   **Proposed Changes**:
    *   Six section cards, each showing its values or "Not set".
    *   A disclosure line per card, with the extra lines for the two free-text sections.
    *   Tapping a card opens that section's editor sheet.

**20. `apps/mobile/lib/features/profile/widgets/profile_section_editors.dart` (Create)**

*   **Type / Scope**: Editor sheets.
*   **Proposed Changes**: One editor per section:
    *   **About you:**
        *   a sex segmented control (Female / Male / Not set);
        *   a birth year picker from `reference_year − 130` to the current year;
        *   height in centimetres, or feet plus inches under the imperial unit system, stored
            as total inches.
    *   **Training Goals:** chips, plus **None**.
    *   **Experience:**
        *   one row per active Focus, with a Beginner / Intermediate / Advanced / Not set
            selector and its one-line meaning;
        *   entries for archived Focuses are hidden but kept;
        *   **None**.
    *   **Training setup:**
        *   equipment chips from `ExerciseEquipment.known`, plus **None**;
        *   a days-per-week stepper (1–7, Not set);
        *   session length in minutes (Not set allowed).
    *   **Health & limitations:**
        *   a text field with a counter at 1,000;
        *   a **None** toggle that clears the text;
        *   the medications line.
    *   **General Notes:** a text field with a counter at 2,000.
    *   Every editor:
        *   has ≥ 48 dp targets and labels for screen readers;
        *   takes all styling from theme tokens.

**21. `apps/mobile/lib/features/home/widgets/home_screen.dart` (Modify)**

*   **Type / Scope**: Account & app sheet.
*   **Proposed Changes**: Add a **Profile** tile between account status and Settings, opening
    file 19.

**22. `apps/mobile/lib/l10n/app_en.arb` (Modify)** and generated `app_localizations*.dart`

*   **Type / Scope**: Copy.
*   **Proposed Changes**: All strings from the Technical Plan, verbatim:
    *   the disclosure lines, with a `{server}` placeholder;
    *   the section and field labels;
    *   the level meanings;
    *   the None labels;
    *   the soft-warning messages;
    *   the medications line.

#### Server

**23. `apps/server/src/db/schema.ts` (Modify)** and
**24. `apps/server/drizzle/0035_user_profile.sql` (Create, generated)**

*   **Type / Scope**: Postgres schema and migration.
*   **Proposed Changes**:
    *   Add `userProfileSections` and `userProfilePrompts`, each with:
        *   `id` (primary key);
        *   `userId`, referencing `user.id` with `onDelete: "cascade"`;
        *   `payload` (jsonb);
        *   `deviceId`, `updatedAt`, `deletedAt`, `receivedAt`;
        *   an index on `userId`.
    *   The migration is additive.

**25. `apps/server/src/sync.ts` (Modify)**

*   **Type / Scope**: Sync push and pull.
*   **Proposed Changes**:
    *   Add `USER_PROFILE_SECTIONS_SYNC_ENTITY = "user_profile_sections"` and
        `USER_PROFILE_PROMPTS_SYNC_ENTITY = "user_profile_prompts"` to `SYNC_PUSH_ENTITIES` and
        `SYNC_PULL_ENTITIES`.
    *   Push both with row-level LWW, copying `nutrition_goals`, including the tenant-isolation
        check.
    *   Validate section payloads through file 5. On a hard error, reject only that change,
        with the existing per-change rejection.
    *   Add an optional `pushEntities: string[]` to `SyncPullResponseSchema`, filled from
        `SYNC_PUSH_ENTITIES`. It is additive, so `SYNC_PROTOCOL_VERSION` stays 2. Comment this
        as for `PROTOCOL_SKIPS_SYNC_ENTITY`.
    *   Neither entity has a parent, so neither goes in the parent-ordering switch.

**26. `apps/server/src/agent-profile.ts` (Create)**

*   **Type / Scope**: Agent REST routes.
*   **Proposed Changes**:
    *   Zod and OpenAPI schemas:
        *   `AgentProfileSchema`, a section map with `{ values, updated_at } | null` per
            section, where Experience entries add `focus_name` and `archived`;
        *   `AgentProfileBatchWriteRequestSchema`, with `batch_id`, `sections` and
            `confirm_warnings`;
        *   `AgentProfileBatchWriteResponseSchema`, a union of `applied` and
            `needs_confirmation`.
    *   **`readAgentProfile`** reads the newest live row per section, ordered by `updated_at`
        and then `id`, like `agent-nutrition-goals.ts`.
    *   **`batchWriteAgentProfile`**:
        1. Checks idempotency by `activityLog.batchId`, as in `agent-settings.ts`.
        2. For each named section, merges the given fields into the current values: absent
           means keep, `null` means clear, a list replaces the whole list.
        3. Validates with `referenceYear` set to the server's current UTC year.
        4. Returns `needs_confirmation` if needed.
        5. Otherwise, in one transaction, updates the newest row in place or inserts a new row
           with a random UUID, and appends one Activity Log Batch with before and after images.
        6. Sends the existing sync nudge.
    *   Register both routes on the agent router.

**27. `apps/server/src/agent-mcp.ts` (Modify)**

*   **Type / Scope**: MCP tools, registered by hand.
*   **Proposed Changes**:
    *   Register `agent_read_profile` and `agent_batch_write_profile`, which call file 26's
        handlers.
    *   The write tool's result reuses the settings write-result pattern, including the sync
        nudge.
    *   The tool descriptions say that every connected agent can read the profile, and that
        values are user-provided and not medical advice.

**28. `agent-skills/perennia/scripts/prn-agent.mjs` (Modify)**

*   **Type / Scope**: Agent skill CLI.
*   **Proposed Changes**: Add `profile read` and `profile write --file <json>` commands mapping
    to the two operations.

**29. `apps/server/src/agent-activity.ts` (Modify)**

*   **Type / Scope**: Agent activity and undo.
*   **Proposed Changes**:
    *   Add `user_profile_sections` to `UNDOABLE_ENTITY_REGISTRY`. Undo restores the
        before-image and refuses when the current image differs from the recorded after-image,
        as the existing entries do.
    *   In the activity read, for changes whose entity is `user_profile_sections` and whose
        payload section is `health_limitations` or `general_notes`, replace the before and after
        `values` with `{ "redacted": true }`.
    *   Prompt rows are not undoable.

**30. `apps/server/src/observability.ts` (Modify)**

*   **Type / Scope**: Log scrubbing.
*   **Proposed Changes**: Add the keys listed under Lifecycle in the Technical Plan to the
    profile deny-list used by `shouldFilterKey`.

**31. `packages/contract/openapi.json`, the generated `agent-client.ts`, and the generated Dart API client (Modify, generated)**

*   **Type / Scope**: Contract.
*   **Proposed Changes**:
    *   Regenerated.
    *   The diff shows the two new operations, their schemas, and the optional `pushEntities`
        on `SyncPullResponse`.

#### Server tests

**32. `apps/server/test/agent-profile.test.mjs` (Create)**

*   **Type / Scope**: Integration tests against Postgres.
*   **Proposed Changes**:
    *   Read when empty.
    *   Partial write: an absent field is kept and `null` clears.
    *   A list replaces the whole list.
    *   A hard reject writes nothing.
    *   `needs_confirmation`, then a confirmed write.
    *   Idempotent `batch_id`.
    *   Newest-per-section read when two rows exist.
    *   Undo, and undo refused after an intervening change.
    *   Redaction of the two free-text sections in the activity read, with the other sections
        not redacted.

**33. `apps/server/test/user-profile-lifecycle-sync.test.mjs` (Create)**

*   **Type / Scope**: Sync tests.
*   **Proposed Changes**:
    *   Push and pull of both entities.
    *   Tenant isolation, where a foreign id is dropped.
    *   `pushEntities` is present and includes both entities.
    *   LWW between two devices on one section.
    *   Two devices on different sections both survive.
    *   Prompt rows from two devices both kept.

**34. `apps/server/test/agent-mcp.test.mjs` (Modify)**,
**`apps/server/test/observability.test.mjs` (Modify)**, and
**`apps/server/test/account-deletion-purge.test.mjs` (Modify)**

*   **Type / Scope**: Existing suites.
*   **Proposed Changes**:
    *   **MCP:** add the two tool names to the expected list.
    *   **Observability:** assert that each new key is scrubbed.
    *   **Account deletion:** assert that both tables are empty for the user after purge.

#### Device tests

**35. `apps/mobile/test/data/user_profile_repository_test.dart` (Create)**

*   **Type / Scope**: Repository tests against in-memory SQLite.
*   **Proposed Changes**:
    *   Save and watch.
    *   Unset versus none.
    *   Clear a field.
    *   Validation errors and the confirmation flow.
    *   Newest-per-section when two rows exist.
    *   Unsynced-fill rule (CUJ 5): local set values win, local nulls take remote values, and a
        previously synced row uses plain LWW.
    *   Device undo restores a section.
    *   Prompt `markDone` is idempotent and `isDone` is a union across rows.
    *   Portable archive round trip, merge-only.
    *   Erase-all clears both tables.

**36. `apps/mobile/test/features/sync/user_profile_sync_gating_test.dart` (Create)** and
**`apps/mobile/test/features/profile/profile_screen_test.dart` (Create)**

*   **Type / Scope**: Sync gating, widget and accessibility tests.
*   **Proposed Changes**:
    *   **Gating:** with no `pushEntities`, both entities stay pending and others push. After a
        pull that lists them, they push.
    *   **Profile screen:**
        *   each of the three disclosure states renders its exact copy;
        *   the two free-text sections show their extra lines;
        *   editors meet the ≥ 48 dp target and the semantics labels;
        *   layout holds at 200% text scale;
        *   the soft warning saves on the second tap.

#### Docs (Stage 1)

**36a. `CONTEXT.md` (Modify)**

*   Add User Profile, Training Goal and Profile Prompt as defined in the Technical Plan.
*   Widen Equipment.
*   Add "not the User Profile" to Record Profile.

**36b. `ARCHITECTURE.md` (Modify)**

*   In Sync, add the two entities, the unsynced-fill rule, and `pushEntities` gating.

**36c. `DESIGN.md` (Modify)**

*   Add a component for the disclosure line (supporting text style, under the section card).
    Stage 2 adds the onboarding screen component.

**36d. `CHANGELOG.md` (Modify)**

*   Added: "Profile under Account & app, with agent read and write."

### Stage 2: onboarding and the rule change

**37. `apps/mobile/lib/features/onboarding/repositories/onboarding_gate.dart` (Create)**

*   **Type / Scope**: Repository-layer query.
*   **Proposed Changes**: `Future<bool> shouldShowOnboarding()` is true when all of these hold:
    *   `isDone("onboarding")` is false;
    *   no live `UserProfileSections` row exists;
    *   there is no live row in any of these tables:
        *   `WorkoutSessions`;
        *   `WorkoutTemplates`;
        *   `PlanRoutines`;
        *   `FoodEntries`;
        *   `Protocols`;
        *   `MetricReadings` with `provenance = 'manual'`.

    These are existence queries with `LIMIT 1`. The docstring explains that the authored-data
    condition stands in for a migration marker for pre-release installs.

**38. `apps/mobile/lib/features/onboarding/controllers/onboarding_controller.dart` (Create)**

*   **Type / Scope**: Controller, a small state machine.
*   **Proposed Changes**:
    *   States: `screen1`, `screen2`, `screen3`, `done`.
    *   `next()` saves the current screen. On screens 2 and 3 that is one Batch. On screen 1,
        `markDone("onboarding")` shares the About you section's Batch.
    *   `skipThis()` saves nothing for the screen. On screen 1 it calls `markDone`.
    *   `skipAll()` calls `markDone` if not done, then goes to `done`.
    *   `back()` is available on screens 2 and 3.
    *   Screen 1 follows the save order under Onboarding flow in the Technical Plan. Its four
        steps call, in turn, `SettingsController.setUnitSystem` and `setWeekStartDay`,
        `MeasurementRepository.ensureDefaultMeasurements`, `userProfile.saveSection(aboutYou)`,
        and `MeasurementRepository.createEntry` on Body Weight.
    *   The weight field is hidden if no active Metric named Body Weight exists after step 2.
    *   `signIn()` opens the existing sign-in flow and writes nothing. When the user returns
        signed in, the controller awaits the first Sync Run result, then calls
        `shouldShowOnboarding()`. If true, it returns to `screen1`; if false, it goes to
        `done`.

**39. `apps/mobile/lib/features/onboarding/widgets/onboarding_flow.dart` (Create)**

*   **Type / Scope**: Screens.
*   **Proposed Changes**:
    *   The three screens, using the editors from file 20 for their fields, plus the units and
        week start controls.
    *   Every screen has **Skip all** in the app bar and **Skip this** and **Next** at the
        bottom. Screen 3's Next reads **Done**.
    *   Screen 1 has the **Already use Perennia? Sign in** link.
    *   The disclosure line sits in the footer.
    *   Nothing asks for an OS permission.

**40. `apps/mobile/lib/app.dart` (Modify)**

*   **Type / Scope**: App start.
*   **Proposed Changes**: After the database opens, await `shouldShowOnboarding()`. If true,
    show `OnboardingFlow` before the Today root; on `done`, replace it with Today. The check
    runs only at start-up.

**41. `apps/mobile/lib/l10n/app_en.arb` (Modify)**

*   **Type / Scope**: Copy.
*   **Proposed Changes**: The onboarding screen titles, buttons and sign-in link.

**42. `apps/mobile/test/features/onboarding/onboarding_flow_test.dart` (Create)**

*   **Type / Scope**: Widget and controller tests against in-memory SQLite.
*   **Proposed Changes**:
    *   CUJs 1, 2, 3 (kill and reopen on screen 1 and on screen 2), 4 and 11.
    *   The gate is false with only a manual Metric Reading.
    *   Weight hidden when Body Weight is archived.
    *   Body Weight seeded in pounds under Imperial.
    *   Screen 1 writes the settings, the About you section with the dismissal, and the
        reading in that order. Undoing the About you Batch leaves the reading and settings
        intact.
    *   Accessibility: targets, semantics, 200% text scale.

**43. `AGENTS.md` (Modify)**

*   Replace the "No onboarding wizards" bullet with the text given in the Technical Plan.
*   Add Profile under Account & app in the Screen map.

**44. `DESIGN.md` (Modify)**

*   Add the onboarding screen component: app-bar Skip all, bottom action row, footer
    disclosure.

**45. `CHANGELOG.md` (Modify)**

*   Added: "Optional first-open onboarding, skippable from its first screen."

### Verification Plan

*   **Gate**: `pnpm ci:local mobile golden contract js sync release_version` must pass for each
    stage. The `js` and `sync` jobs need Docker running.
*   **Unit and repository tests**:
    *   files 7 and 35, and the v64 → v65 migration test (file 11);
    *   files 36 and 42.
*   **Golden vectors**: files 6 and 7 run the same `m38` cases. File 7 also pins the TypeScript
    equipment ids to the Dart registry.
*   **Server integration**: files 32, 33 and 34, against the ephemeral Postgres.
*   **Sync simulation**:
    *   CUJs 5 and 9 in file 33 (server) and file 35 (device fill rule);
    *   the gating test in file 36.
*   **Kill and reopen**: CUJ 3 in file 42. The logging path is unchanged, so the standing
    mid-workout scenario needs no new case.
*   **Accessibility**: the 48 dp, semantics and 200% text-scale assertions in files 36 and 42.
*   **Contract**: the `contract` job's diff check shows only the additions listed in file 31.
*   **Manual check before Stage 2 merges**:
    1. On a release build on a device, install fresh, then: Skip all; kill on screen 1; sign
       in from screen 1 against a staging account that has a filled profile.
    2. Confirm the privacy policy covers the User Profile before the first hosted release that
       contains Stage 1.
