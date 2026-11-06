# Compound Purposes and Protocol Building

*   **Author:** Leonardo Pinheiro
*   **Status:** Current
*   **Date:** 2026-11-04

--------------------------------------------------------------------------------

## Overview

Perennia's Protocols domain records what a user takes. A **Compound** is an
item in the user's own library, a **Dose** is one logged administration of it,
and a **Protocol** is a named course of one or more Compounds, each with a
**Schedule**. These terms are defined in [CONTEXT.md](../../CONTEXT.md). The
Protocol model, its Schedules and its reminders are specified in
[Protocol Schedules and Reminders](protocol-schedules-and-reminders.md) (the
"Protocol schedules spec" below). This spec changes one rule stated there, the
neutral-instrument rule, and updates that spec in the same pull request (PR)
that changes the rule (PR 2, file 39). How the app, sync and the agent surface fit
together is in [ARCHITECTURE.md](../../ARCHITECTURE.md). The project's rules
and invariants are in [AGENTS.md](../../AGENTS.md), and the visual system is in
[DESIGN.md](../../DESIGN.md).

This spec does three things:

1.  **It lets a user edit and archive a Compound.** Today the app has no way to
    do either, and tagging an existing Compound needs one.
2.  **It reshapes the Protocol editor around its Compounds.** The Compounds and
    their Schedules come first. Compounds are added from a picker sheet with
    search, and a missing Compound can be created there without leaving the
    editor.
3.  **It adds Purposes.** A **Purpose** is a label for why a user takes a
    Compound, such as Sleep or Performance. The user owns the labels and can tag
    a Compound with any number of them. The app seeds a starter set of names
    and tags its six built-in Compounds with them. The picker and the Compound
    list filter by Purpose.

It narrows one existing rule. The app has never categorized a Compound. Under
this spec it may tag its own six built-in Compounds with Purposes, and it still
never classifies a Compound by what it is or whether it is legal (see
[The neutral-instrument rule, narrowed](#the-neutral-instrument-rule-narrowed)).

In this spec, **OTC** means over the counter: sold without a prescription. The
six built-in Compounds are all OTC.

## The Problem

The problems below were found by running the app at release 0.2.0 on an Android
emulator holding a library of 11 Compounds and 3 Protocols.

### Building a Protocol

1.  **The Compounds are buried.** New Protocol asks, in order, for:
    1.  a name and a start date;
    2.  the Period, the Cycle and the Pauses;
    3.  the Compounds;
    4.  a Schedule for each Compound;
    5.  Reminders, then Target outcomes.

    The Compounds and their Schedules are what a Protocol is. We assume most
    Protocols leave the rest at their defaults ("ongoing, no cycle, no
    pauses"); that is a design assumption, not a measurement.
2.  **The picker doesn't scale.** Every active Compound is a chip in one wrap,
    sorted by name, with no search or filter. At 11 Compounds the wrap fills
    a third of the screen, so it fills about one screen per 33 Compounds.
3.  **A missing Compound costs the user the form.** The editor can't create a
    Compound. The user has to leave New Protocol to make one, and leaving it
    discards the form without asking. Anything already entered is lost:
    the name, the dates, the cycle and the other Schedules.
4.  **The Schedules crowd each other out.** Each selected Compound adds about a
    screen of Schedule controls under the chips. With two Compounds selected,
    the chips are no longer on screen, so adding a third means scrolling back
    up past both editors.
5.  **A new member plans nothing.** A newly selected Compound starts on **No
    schedule**. It plans no doses and gets no reminder until the user changes
    that. We assume planning doses and reminders is why most users write a
    Protocol (a design assumption).
6.  **A Protocol with an archived Compound can't be saved.** The repository
    refuses to save a Protocol if any of its members' Compounds is archived,
    even when the user changed nothing about that member.

### The Compound library

7.  **There is no way to group Compounds.** The list and the picker are
    alphabetical, and search matches names only. We assume a user with many
    Compounds thinks in terms of why they take something ("what am I taking
    for sleep?"), and nothing in the app records that.
8.  **A Compound can't be changed once it's created.** In the Compound list,
    tapping a row logs a Dose, the chart icon opens Consistency (the Protocol
    schedules spec's per-Compound adherence view), and the star sets a
    favorite. Nothing lets the user rename a Compound, fix its default unit,
    route or strength, or archive one they no longer take. Any new attribute,
    Purposes included, needs this surface first.
9.  **Some of the copy is hardcoded English.** The New compound sheet and the
    list's search field are written in English in the code, outside the ARB
    (Application Resource Bundle) files, so they can't be translated.

## Goals

1.  **Create a missing Compound without leaving the Protocol.** From the
    Compound picker, a user who types a name that doesn't exist creates it and
    returns to the picker with it selected. Nothing entered in the Protocol is
    lost.
2.  **Make picking work at 200 Compounds.** The picker narrows on every
    keystroke within one frame, filters by Purpose, shows Favorites and Recent
    first, and keeps the selection while the search or the filter changes.
3.  **Add Purposes that the user owns.**
    *   The app seeds six names: Sleep, Body composition, Performance,
        Recovery, Cognition and General health.
    *   The user can rename, reorder, archive and add Purposes, and tag a
        Compound with any number of them.
    *   Purposes work the way Focus does for exercises.
4.  **Tag the built-in Compounds.** The six built-in Compounds arrive tagged,
    on a new install and on an upgrade. After that, a tag is the user's: a tag
    the user removes stays removed, on every device, under the same
    last-writer-wins rule as every other field. A Purpose the user renamed or
    archived is never restored by the seed.
5.  **Edit and archive a Compound.** The user can change a Compound's name,
    default unit and route, strength and Purposes, and archive it. Logged Doses
    never change, because each Dose already stores a snapshot of its Compound.
6.  **Put the Compounds first in the Protocol editor.**
    *   Members are rows that each show a one-line Schedule summary.
    *   One Schedule editor is open at a time.
    *   A Compound the user adds defaults to every day at one set time.
    *   The period settings collapse to one line.
    *   Leaving with unsaved changes asks before discarding them.
    *   A Protocol whose member's Compound is archived can be saved.
7.  **Filter the Compound list by Purpose,** and match Purpose names in its
    search.
8.  **Give Agents the Purpose operations.** Agents can list Purposes, create,
    rename, reorder and archive them, read and set a Compound's Purposes, and
    filter Compounds by Purpose. Editing and archiving a Compound is already on
    the agent surface and doesn't change.
9.  **Move the Compound list's copy into the ARB files.** This covers the New
    compound sheet and the list's search field.

## Non-Goals

*   **A larger built-in library.** Which Compounds the app ships, and whether
    any beyond the six existing ones get Purposes, is a separate spec. This
    spec tags only the six OTC Compounds the app already ships.
*   **Any wording that a Compound works.** A Purpose is shown only as its name:
    "Sleep", never "for sleep", "helps sleep" or "supports sleep".
*   **Analysis by Purpose.** The Effect view, Consistency, Day Statuses and the
    Progress card never read Purposes.
*   **Purposes on a Protocol.** A Protocol has no Purposes of its own.
*   **Purpose colors.** A Purpose is always shown as text, so it needs no color.
    Focus has colors because Training is drawn in them, and nothing in this spec
    draws in Purpose colors.
*   **Changes to Schedules, reminders, Day Statuses or Skips.** Their behavior
    stays as the Protocol schedules spec defines it. The editor's layout, the
    default for an added member and the archived-member save change; nothing
    about what a saved Schedule plans changes.
*   **Changes to the Agent Protocol write.** The server's Protocol batch write
    has no active-Compound check today, and this spec adds none (D4).
*   **Merging duplicate Compounds,** or warning about a near-duplicate name.
*   **A tablet or landscape layout** for the editor. It keeps today's
    single-column layout.

## Open Questions

None. The draft's one open question, whether Magnesium is tagged Sleep or
Recovery, was settled by the maintainer: Sleep, one Purpose per seed Compound,
as the D3 table shows.

## New and changed terms

| Term | Definition | Added to CONTEXT.md |
| :--- | :--------- | :------------------ |
| **Purpose** (new) | A label for why the user takes a Compound, such as Sleep or Performance. Perennia seeds a starter set and tags its own built-in Compounds with them; users rename, reorder, archive and add their own, and tag any Compound with any number of them. Never a claim that a Compound works, never a classification of what a Compound is, and never read by analysis. Freely changeable: changing or archiving a Purpose never alters a Dose. Distinct from Focus, which is for exercises, and from a Protocol's target outcomes, which name what to correlate. | yes |
| **Compound** (changed) | The sentence beginning "The app ships only…", which today reads "The app ships only a few over-the-counter examples and never categorizes a Compound by what it is", becomes: "The app ships only a few over-the-counter examples, tagged with Purposes, and never classifies a Compound by what it is or whether it is legal." | yes |

Two phrases are used throughout this spec without being CONTEXT.md terms:

*   **A live member** is a Protocol Member that isn't archived (no
    `archived_on`) and isn't tombstoned by undo.
*   **A member whose Compound is archived** is a live member whose Compound row
    has `deletedAt` set.

## The neutral-instrument rule, narrowed

The Protocol schedules spec states the rule as: *the app never categorizes a
Compound by what it is or whether it is legal.* This spec replaces that line
with three:

*   **The app never classifies a Compound by what it is or whether it is
    legal.** It has no type, class, schedule or legality field, anywhere.
*   **The app tags only its own OTC built-in Compounds with Purposes,** and
    only with the seeded Purpose names. The tags record what people commonly
    take these items for. They never say that the items work.
*   **Once seeded, a tag belongs to the user.** The user can remove it, and the
    seed never adds it again.

The rest of the rule is unchanged: no dosing advice, no sourcing, no claims
that anything works, and the "For personal tracking; not medical advice."
notice on the Effect view.

**The risk this accepts.** A tag the app ships reads as a suggestion of what
the Compound is for. For creatine and Performance, or melatonin and Sleep, it
matches the label on the bottle. The risk grows with the library. A peptide or
a hormone tagged by the app would be close to an off-label claim. That is
why the narrowing covers only OTC items. Extending it is a decision for the
spec that grows the library (see [Risks](#risks-and-mitigations)).

## Critical User Journeys (CUJs)

### CUJ 1: A sleep Protocol with a Compound the user doesn't have yet

*   **Given**: The user's library holds the six built-in Compounds and a few of
    their own. Melatonin is tagged Sleep, and the latest Melatonin Dose was
    3 mg. There is no Glycine.
*   **When**: The user taps New Protocol, types "Sleep stack", and taps **Add
    Compounds**. In the picker they tap the **Sleep** filter, select Melatonin,
    type "Glyc" in search, and tap **Create "Glyc"**. In the Compound editor
    sheet they correct the name to "Glycine", set the unit to g, see Sleep
    already tagged, and save. They tap **Done**.
*   **Then**: The picker returned with Glycine selected next to Melatonin. The
    editor shows two member rows, "Melatonin · Every day · 9:00 · 3 mg" and
    "Glycine · Every day · 9:00 · Add an amount", and the name "Sleep stack" is
    still there. Glycine is in the library tagged Sleep, whether or not the
    user saves the Protocol.

### CUJ 2: Setting a member's Schedule

*   **Given**: CUJ 1's editor, unsaved.
*   **When**: The user taps the Glycine row. A sheet opens with Glycine's
    Schedule editor. They set the time to 22:00 and the amount to 3, and close
    the sheet.
*   **Then**: The row reads "Glycine · Every day · 22:00 · 3 g". Only one
    Schedule editor was ever open. Turning on Reminders and saving plans a
    22:00 dose every day, exactly as the Protocol schedules spec defines.

### CUJ 3: Leaving by mistake

*   **Given**: An unsaved New Protocol with a name and one member.
*   **When**: The user presses Back.
*   **Then**: A dialog asks **Discard this Protocol?** with **Keep editing** and
    **Discard**. Keep editing returns to the form as it was. An editor with no
    changes closes without asking.

### CUJ 4: 200 Compounds

*   **Given**: A library of 200 active Compounds, 12 of them tagged Performance
    and 3 favorites.
*   **When**: The user opens the picker, taps **Performance**, then types "cr".
*   **Then**: The list shows Favorites and Recent that match, then the matching
    Compounds A–Z, narrowing within one frame on each keystroke. Clearing the
    filter or the search keeps every selection made so far. The count on
    **Done** ("Done · 3") always shows how many listed Compounds are selected.

### CUJ 5: Retagging an existing Compound

*   **Given**: A user-created Compound "Ashwagandha" with no Purposes.
*   **When**: In the Compound list, the user long-presses it. The Compound
    editor sheet opens in edit mode. They tap Sleep and Recovery and save.
*   **Then**: Ashwagandha appears under the Sleep and Recovery filters in the
    list and in the picker. Its logged Doses are unchanged. Tapping the row
    without a long-press still opens the log sheet.

### CUJ 6: A removed seed tag stays removed

*   **Given**: Creatine arrived tagged Performance. On device A, the user
    removed that tag and renamed the Purpose "Cognition" to "Memory". Device A
    has synced.
*   **When**: Device A restarts and updates to a newer build. Device B signs in
    to the same account for the first time and syncs.
*   **Then**: On both devices Creatine is untagged, "Memory" keeps its name,
    and no "Cognition" Purpose appears. If device B, before its first pull, had
    edited Creatine itself, the later of the two edits wins, and the other is
    recoverable from the Activity Log, as for every other field.

### CUJ 7: Archiving a Compound a Protocol uses

*   **Given**: Caffeine is a live member of the Protocol "Training days".
*   **When**: The user edits Caffeine and taps **Archive**.
*   **Then**: A dialog says **Caffeine is in 1 active Protocol. Archiving hides
    it from the list and the picker; the Protocol keeps it.** On Archive, the
    Compound leaves the list and the picker. Its Protocol membership, its
    Schedule, its reminders and its logged Doses are unchanged, as an archived
    exercise keeps its history. Editing "Training days" later shows Caffeine's
    row marked **Archived**, and saving the Protocol succeeds (today it is
    refused; see D4).

### CUJ 8: Managing Purposes

*   **Given**: The six seeded Purposes.
*   **When**: The user opens **Purposes** from the Compound list's menu,
    archives General health, adds "Skin", and drags Skin to the top.
*   **Then**: The filter rows in the list and the picker show Skin first and no
    longer show General health. Compounds tagged General health keep the tag.
    Undoing the archive from the Activity Log restores the Purpose, and the tag
    shows again. If an active Purpose named "General health" exists by then,
    the undo is reported as not applied (`duplicatePurposeName`).

### CUJ 9: An Agent does the same

*   **Given**: The user's Agent, with a key that has Protocols access, and the
    six built-in Compounds with their seed tags.
*   **When**: The Agent lists the Purposes, creates a Compound "Glycine" with
    the Sleep Purpose, and lists Compounds filtered by Sleep.
*   **Then**: The list returns Magnesium, Melatonin and Glycine. The app shows
    Glycine tagged Sleep after its next sync.

## Technical Plan (Architecture)

### Shape of the change

```text
  PR 1 (no schema change)                 PR 2 (Purposes end to end)
  ───────────────────────                 ──────────────────────────
  Compound editor sheet: edit, archive    purposes table, compounds.purposeIds
  Protocol editor: rows, sheet, When,     seed: starter Purposes, tags at insert,
    discard prompt, added-member default    one-time backfill of untouched rows
  Compound picker: search, inline create  sync: `purposes` entity, `purpose_ids`
  archived-member save fix                Agent: Purpose ops, purposeIds, filter
  copy to ARB                             filter rows, Purpose manager

              ┌──────────────── app (Drift) ────────────────┐
              │ purposes                compounds.purposeIds│
              │ (id, name, sortOrder,   (JSON string array, │
              │  updatedAt, deletedAt)   default '[]')      │
              └───────┬────────────────────────┬────────────┘
                      │ sync: `purposes`,      │ UI: list filter, picker,
                      │ `purpose_ids` on       │ editor sheet, Purpose manager,
                      │ `compounds`            │ reshaped Protocol editor
                      ▼                        ▼
              ┌──────────────── server (Postgres) ──────────┐
              │ purposes (account-keyed, like focuses)      │
              │ compounds payload carries purpose_ids       │
              │ forward when a push omits it                │
              └───────────────────────┬─────────────────────┘
                                      ▼
              Agent REST + MCP: list/write Purposes, purposeIds on
              Compounds, `purpose` filter on the Compound list
```

### Invariants

*   **Derived analytics are computed, never stored.** Nothing derived is added.
    A Compound's Purposes are stored data the user owns, not a result, and no
    analysis reads them.
*   **User-facing delete = archive.** Archiving a Purpose sets its tombstone.
    Archiving a Compound sets its tombstone and cascades nothing: its tags,
    its Protocol memberships, its Schedules and its Doses stay (D4).
*   **Sync is silent last-writer-wins with recoverable losers.** Purposes sync
    like Focuses. A Compound's tags are one field of its row, so a concurrent
    edit on another device can win; the loser is in the Activity Log. The
    server carries `purpose_ids` forward when a push omits it, so a client or
    Agent that doesn't send it never erases it (D2).
*   **Restore and import are merge-only.** The portable archive gains the
    `purposes` entity, imported by merge like every other entity. An archive
    written before this change has no Purposes and imports as before.
*   **Validation is one shared module.** The Purpose name rules and the id
    normalization are written once in Dart and once in TypeScript, and are
    pinned together, with the starter set, by the golden vectors
    `m40-compound-purposes` (D8).
*   **Local writes never block on the network.** Creating a Compound from the
    picker, tagging and editing are local writes, like every Protocols write.
*   **The others** (Workouts as sessions, self-describing Sets, no behavioral
    analytics) are untouched.

### D1. Purposes: storage and sync (PR 2)

A Purpose is a row in a new table, modelled on `focuses` but without a color.

*   **App (Drift):** table `Purposes` (SQL `purposes`), with columns:
    *   `id` text, the primary key;
    *   `name` text, stored trimmed;
    *   `sortOrder` int;
    *   `syncDeviceId` and `syncPreviouslySynced`;
    *   `updatedAt`;
    *   `deletedAt`, the archive tombstone.

    The schema version goes up by one, to the next free one (66 at the time
    of writing, from 65). The migration step `from < 66`:
    *   creates the table and adds `compounds.purpose_ids` (D2), each only if
        missing, following the `from < 59` Focus step;
    *   clears `sync_states.pull_cursor`, so the next Sync Run pulls every
        entity from the start (see "Older clients" below).
*   **Sync entity `purposes`:**
    *   **App payload:** `{id, name, sort_order, updated_at, deleted_at}`.
    *   **App path:** the generic `_PlanSyncEntity` path that Focus uses in
        `sync_repository.dart`, with local apply order 0, next to Focus. A
        Purpose is only a soft reference from a Compound, so the slot is tidy
        ordering, not a dependency.
    *   **Server:** table `purposes`, keyed `(user_id, id)` because the
        starter ids are shared by every account. It is pushed through
        `pushAccountKeyedSyncRowsInTransaction`, like `focuses` and
        `compounds`, through a new `pushPurposesInTransaction`.
    *   **Server pull order:** rank 1.5, so Purposes arrive before Compounds
        (rank 2). A Compound naming a Purpose that hasn't arrived yet is fine.
        The list is a soft reference, as `focus_ids` is.
*   **Older clients.** A client built before this change skips the unknown
    `purposes` entity but still advances its pull cursor past those changes.
    When that device later upgrades, it would never pull the Purposes it
    skipped. The `from < 66` step clears the stored pull cursor, so the first
    Sync Run after the upgrade is a full pull. The sync protocol version stays
    2.

    It also applied `compounds` rows but had no column for `purpose_ids`, so it
    stored the row's `updated_at` and device id and lost the tags. The full pull
    returns that same version, an exact last-writer-wins tie that applies
    nothing, and the row would stay at the column default, count as touched
    (D3), and push an explicit `[]` on its next edit. So when a pulled Compound
    loses last-writer-wins but is the same version (equal `updated_at`, equal
    device id), carries a `purpose_ids` other than `'[]'`, and the local column
    still holds `'[]'`, the app writes only `purpose_ids`. It keeps `updated_at`
    and writes no Activity Log entry, because the log already holds this
    version's entry and nothing needs pushing. A local list that isn't `'[]'`
    was stored by a build that has the column, so it is left alone.
*   **The Protocols domain's privacy is unchanged.** Purposes are Protocols
    data:
    *   they sit behind the Protocols lock;
    *   they are left out of the CSV export;
    *   they are included in the portable archive;
    *   they sync like the rest of the domain. As
        [ARCHITECTURE.md](../../ARCHITECTURE.md#sync) states, the server stores
        and reads these payloads. They are not end-to-end encrypted.
*   **Erase all data** removes user-created Purposes and keeps seed-owned rows:
    the six starter Purposes and the six seed Compounds survive with their
    names and tags, as Focuses' starter rows do.

### D2. Tags on a Compound (PR 2)

A Compound's tags are a list of Purpose ids on the Compound itself, the way an
Exercise's Focuses are `focus_ids`. There is no join table:

*   **App:** column `compounds.purposeIds`, non-null text holding a
    JSON-encoded string array, default `'[]'`.
*   **Payload:** key `purpose_ids`, a JSON-encoded string, as `focus_ids` is.
    The server writes it with `JSON.stringify` and reads it with
    `parseJsonStringArray`.
*   **The stored list is the list.** What is stored is what the app, sync and
    Agents read. There is no computed default and no read-through rule.
*   **Order is kept.** The list keeps the order the user tagged in. It is
    deduplicated (keeping the first occurrence) but never sorted.
*   **Purpose renames and archives are safe.** Tags hold ids, so renaming a
    Purpose changes no Compound. A Compound tagged with an archived Purpose
    keeps the id. The UI shows only active Purposes, and the editor keeps an
    archived id attached without showing a chip, exactly as the Exercise
    editor does for an archived Focus.

**Sync of the key** follows the `color_hex` precedent in
[Progress Overview D6](progress-overview.md#d6-focus-color):

*   **App decode:** a payload with no `purpose_ids` key keeps the local value
    (`_imageNonNullStringIfPresent`, because the column is NOT NULL).
*   **Server:** `SYNC_CARRY_FORWARD_PAYLOAD_KEYS`'s `compounds` entry gains
    `purpose_ids`, next to `is_favorite`, so a push without it, from an older
    app or an Agent edit that omits it, keeps the stored list.
*   **Undo:** an undo image written before this change has no `purpose_ids`
    key; `_activityLaterAddedKeyDefaults[compounds]` gains
    `{'purpose_ids': '[]'}`, matching the column default. Such an image leaves
    the list alone on undo, which is right for a write that never touched it.
    A write that does set the list must record what the row read as: when an
    Agent write sets `purpose_ids` and the stored row lacks the key, its before
    image carries `purpose_ids: '[]'`. Otherwise undo would omit the key,
    carry-forward would keep the tags, and the undo would still report success.
*   **Reading a bad value:** `purpose_ids` reaches the app from sync and
    portable archives unchecked. A string that isn't a JSON array reads as no
    tags, as the server's `parseJsonStringArray` does, and stays stored as it
    is, so one bad value can't break every read of the Compound library.

### D3. Seeds (PR 2)

*   **Starter Purposes.** There are six, with fixed ids in a reserved block
    and the fixed seed timestamp `2026-10-24T00:00:00Z`, the one the Focus
    seed uses:

    | Id | Name | sortOrder |
    | :- | :--- | :-------- |
    | `019200ff-0000-7000-8000-000000000101` | Sleep | 0 |
    | `019200ff-0000-7000-8000-000000000102` | Body composition | 1 |
    | `019200ff-0000-7000-8000-000000000103` | Performance | 2 |
    | `019200ff-0000-7000-8000-000000000104` | Recovery | 3 |
    | `019200ff-0000-7000-8000-000000000105` | Cognition | 4 |
    | `019200ff-0000-7000-8000-000000000106` | General health | 5 |

    They are inserted only if the id is absent, in `ensureOtcLibrarySeeded`,
    even when the OTC Compound seed source is empty. So a starter Purpose the
    user renamed or archived is left alone.
*   **Seed tags, written at insert.** The seed tag table is a Dart constant
    (`seedCompoundPurposeIds`) next to the OTC seed. It covers only the six
    OTC Compounds, per [the narrowed rule](#the-neutral-instrument-rule-narrowed):

    | Compound | Seed id | Purposes |
    | :------- | :------ | :------- |
    | Creatine | `019200ff-0000-7000-8000-000000000001` | Performance |
    | Vitamin D | `019200ff-0000-7000-8000-000000000002` | General health |
    | Caffeine | `019200ff-0000-7000-8000-000000000003` | Performance |
    | Magnesium | `019200ff-0000-7000-8000-000000000004` | Sleep |
    | Melatonin | `019200ff-0000-7000-8000-000000000005` | Sleep |
    | Fish oil | `019200ff-0000-7000-8000-000000000006` | General health |

    `_ensureOtcLibrarySeeded` inserts each absent OTC row with its tags in
    `purpose_ids`. The server has no copy of this table: tags reach it as
    stored data, through sync.
*   **The OTC seed's timestamp is fixed.** Today `_ensureOtcLibrarySeeded`
    stamps each inserted row with the current time.
    *   **The problem:** a second device that seeds before its first pull
        pushes six Compound rows newer than a rename made on the first device,
        and last-writer-wins keeps the seed's name.
    *   **The fix:** the insert stamps the fixed seed timestamp, as the Focus
        seed does. A real edit on any device is always newer than it.
*   **Backfill on upgrade.** A device upgrading from schema 65 already holds
    the six rows, untagged. `backfillSeedPurposes` tags each seed row that is
    **untouched**, which means all of:
    *   its `name` equals the seed name;
    *   its `purpose_ids` is `'[]'`;
    *   it has at least one Activity Log entry, and every entry for it has
        actor `otc_seed`.

    For each untouched row, it writes the seed tags with a new `updatedAt`
    and one Activity Log entry with actor `otc_purpose_seed`, so the change
    syncs and can be undone. This follows `_reconcilePlatformSeedFocuses` in
    `training_repositories.dart`, which writes a customization's Focuses with
    a fresh stamp and an Activity Log entry. The stamp is the current time
    after a pull, and one second past the row's own stamp on a signed-out
    device (see **When it runs**).
    *   **It runs once per row.** After it runs, the row has an
        `otc_purpose_seed` entry, so it is no longer untouched. Any edit by the
        user, an Agent or another device (a pulled change logs an entry with
        its own actor) also makes the row touched. No device setting is
        needed.
    *   **Erase all data** keeps the Activity Log and skips seed-owned rows, so
        it changes nothing here: a row the user touched stays touched after
        Erase, and an untouched row is still backfilled.
    *   **When it runs.** On a signed-out device,
        `ProtocolDayController.ensureOtcLibrarySeeded` runs it after seeding,
        for rows with `syncPreviouslySynced` false only.
        `ProtocolsRepository` has no auth, so the rule lives in the controller;
        if the auth read fails it skips the backfill, and the next open retries.
        A device that signed out keeps its rows, and a row the server holds
        must wait: an edit made elsewhere may be waiting there, a fresh stamp
        would beat it, and a Sync Run pushes before it pulls. That row stays
        untagged until the device signs in again.
        A row with `syncPreviouslySynced` false can have a server copy too,
        because seed ids are shared across an account's devices. So this call
        stamps each row one second past its own `updatedAt`, not the current
        time. Storage keeps whole seconds, and the server drops a tie on
        (stamp, device), so an unchanged stamp would lose to the device's own
        pending `otc_seed` entry and the tags would never reach the server.
        Any edit made elsewhere after this device seeded still wins on first
        sign-in, and an account with no such edit receives the tags.
        On a signed-in device, `RepositorySyncCycleRunner` runs it
        instead, after the pull of each Sync Run that gets that far, before the
        run's final push. So it runs after the full pull that follows the
        upgrade (D1) and sees edits made on other devices first, a failed push
        or pull never reaches it, and the same run pushes what it wrote. It is
        cheap (six rows, one Activity Log query) and does nothing once every
        row is touched.
    *   **A fresh install** inserts the rows already tagged, so the backfill
        finds no row with `'[]'` and does nothing.

### D4. Editing and archiving a Compound (PR 1; Purpose chips in PR 2)

*   **The editor has two modes.** The Compound editor sheet
    (`CompoundEditorSheet`) gains an edit mode for an existing Compound.
    *   **Both modes:** name, strength, default unit and route, as today. PR 2
        adds **Purposes**: a wrap of chips for the active Purposes, any number
        selectable, in the order tapped.
    *   **Edit mode only:** an **Archive** button.
*   **Save calls existing repository methods.** It uses
    `ProtocolsRepository.editCompound` and `createCompound`, which already
    exist. In PR 2, `CompoundDraft` gains `purposeIds`.
    *   **An edit stores what is saved.** The draft carries every field shown,
        and the list of Purposes in the order shown.
    *   **A save that changes nothing writes nothing.** If every field and the
        normalized list equal the stored ones, `editCompound` writes no row and
        no Activity Log entry, and returns null. Its return type becomes
        `Future<String?>`: the batch id, or null for no change.
*   **Validation shows inline.** An empty name shows an inline error instead of
    returning silently as it does today. An unparseable strength shows "Use
    the form 5 mg/capsule" instead of being dropped.
*   **Archive confirms first.**
    *   The dialog counts the Protocols in `listProtocolSummaries()` whose
        `compoundIds` contain the Compound (a controller method, file 3):
        *   with one or more, "Caffeine is in 1 active Protocol. Archiving
            hides it from the list and the picker; the Protocol keeps it.",
            with the count as an ICU plural;
        *   with none, "Archiving hides Caffeine from the list and the picker.
            Its logged Doses stay."
    *   Archive calls the existing `archiveCompound`, which cascades nothing.
    *   Undo from the Activity Log restores the Compound. There is no other
        restore path, the same as for exercises.
*   **A Protocol with a member whose Compound is archived can be saved.**
    *   **The bug:** today `_editProtocol` calls `_requireActiveCompoundRows`
        on every member id, so a Protocol with a member whose Compound is
        archived can't be saved at all. The planner already plans archived
        Compounds (`ProtocolPlanDay.compounds` includes them).
    *   **The new rule:** in `_editProtocol`, an id that is already a live
        member of the Protocol may name an archived Compound; an id being added
        must name an active one. `_createProtocol` is unchanged: every member
        is being added.
    *   **The Agent path is unchanged.** The server's Protocol batch write has
        no active-Compound check today, so it already accepts this, and this
        spec adds no check.
    *   **In the editor:** the member row resolves the name of an archived
        Compound through `watchCompoundsByIds` (file 2), which includes
        archived Compounds, and shows **Archived** next to it. It never shows
        the "Compound" fallback.
*   **How the user reaches it.** In the Compound list, a long-press on a row
    opens the editor sheet in edit mode directly. The row also gets an
    accessibility action named **Edit**. A plain tap still opens the log sheet,
    so the two-tap repeat Dose is unchanged.

### D5. The Protocol editor (PR 1)

The form keeps its state, validation and save path. Its layout and the default
for an added member change. The new order is:

1.  **Name.**
2.  **Compounds.**
    *   **Members:** one row per member, in member order. Each row shows:
        *   the Compound's name, and **Archived** when its Compound is;
        *   a one-line Schedule summary;
        *   a remove button.
    *   **Schedule summaries:**

        | Schedule | Summary |
        | :------- | :------ |
        | At set times | "Every day · 9:00 · 5 g", "Mon, Wed, Fri · 8:00, 20:00 · 2 capsules", "Every 3 days · 9:00 · 250 mcg" |
        | Any time | "Every day · 2 a day · 5 g", "Mon, Wed · 2 a day · 5 g" |
        | As needed | "As needed", which is what the form holds, because this rule carries no amount (D7 `amount_absent`); "As needed · 5 g" when the summary is given an amount |
        | No schedule | "No schedule" |

        Times use the device's time format, and weekday names come from
        `DateFormat.E` for the locale. Counts ("2 a day", "Every 3 days") are
        ICU plurals in the ARB. An amount that's still empty reads "Add an
        amount". Once the user has tried to save, it shows in the error color.
    *   **Editing a member:** tapping the row opens that member's existing
        `_ScheduleEditor` in a bottom sheet. It is bound to the same
        `_ScheduleFieldState`, so closing the sheet keeps every change and
        there is nothing to save inside it. Its plan issues show in the sheet,
        and as the line "Fix this Schedule" in the error color under the row.
    *   **Adding members:** **Add Compounds** under the rows opens the picker
        (D6).
3.  **When.**
    *   **Collapsed:** a row summarizing the period, such as "Starts Nov 4 ·
        Ongoing", "Starts Nov 4 · until Dec 31 · 5 on, 2 off · 2 Pauses", or,
        for a Protocol whose end date has passed, "Ended Dec 31".
    *   **Expanded:** tapping the row shows today's controls in place: start
        date, period, the dose-count helper, cycle and Pauses.
    *   It is collapsed when the editor opens, and it expands itself when a
        save attempt finds a period issue.
4.  **Reminders**, then **Target outcomes**, the error text, **Save**, and
    Archive or Delete, all unchanged.

**The default for an added member.** A Compound the user adds in this editor
session starts **At set times, Every day, 9:00**, in the Compound's default
unit and route.

*   **Only added members.** Members that were already on the Protocol when the
    editor opened keep `_ScheduleFieldState.fromVersion` exactly as today,
    including a member with no Schedule Version.
*   **Its planned amount** is the amount of the Compound's latest Dose that
    isn't deleted, when that Dose's unit matches the default unit. Otherwise
    it is empty, and the row asks for an amount.
*   **"No schedule" stays one tap away** in the Schedule editor.
*   **Removing and re-adding** an existing member in one session restores its
    stored version, as today.

**Unsaved changes.** The form takes a snapshot of its values when it opens:
name, dates, cycle, Pauses, member ids and each Schedule field, reminders and
outcomes.

*   **Leaving with changes asks first.** A `PopScope` blocks Back while the
    current values differ from the snapshot, and opens a dialog:
    *   **New Protocol:** **Discard this Protocol?**
    *   **Editing:** **Discard changes?**
    *   **Buttons:** **Keep editing** and **Discard**.
*   **Leaving without changes doesn't ask.** Adding a member always differs
    from the snapshot, so it always asks.
*   **Saving closes without asking.**
*   **A Compound created in the picker isn't form state.** It is already saved
    to the library and isn't undone by Discard.

This is the first discard prompt in the app; no other screen has a `PopScope`
discard today.

### D6. The Compound picker (PR 1; Purpose filter in PR 2)

`showCompoundPickerSheet(context, {required List<String> selectedIds})`
returns the new selection as an ordered `List<String>`, or null if the user
dismissed the sheet. `selectedIds` holds the active members' Compound ids in
member order.

*   **The sheet is nearly full height,** with a drag handle. It holds:
    *   **Header:** the title **Add Compounds** and a **Done** button that
        shows the count, "Done · 3", once anything is selected. The count is
        the number of listed Compounds selected.
    *   **Search field.** It matches the Compound's name, and from PR 2 the
        name of any of its active Purposes. The focused field's cyan stroke is
        the input-focus exception DESIGN.md already allows.
    *   **Purpose filter row (PR 2):** **All**, then each active Purpose in
        `sortOrder`. One Purpose can be active at a time, and the row scrolls
        sideways (`PurposeFilterRow`, D7).
    *   **The list:**
        *   **Favorites**, then **Recent**, as the Compound list shows them;
        *   then **All compounds** A–Z, headed with the Purpose's name ("Sleep")
            while a filter is active;
        *   each row has the name, "unit · route" and a checkbox, and a tap
            toggles it;
        *   search and the filter both apply to every section.
*   **Create row.** When the search isn't empty and no active Compound's name
    equals it (trimmed, case-insensitive), the last row reads **Create
    "{search}"**.
    *   **What it opens:** the Compound editor sheet in create mode, with the
        name filled in and, in PR 2, the active Purpose filter pre-tagged.
    *   **After saving:** the new Compound is selected and the search is
        cleared.
    *   **With no matches at all,** the Create row is the only row.
*   **The selection outlives the search and filter.** Changing either never
    drops a selection.
*   **Archived members aren't the picker's concern.** The picker lists only
    active Compounds and never sees a member whose Compound is archived. The
    editor keeps those members itself and merges them back after Done (file
    6).
*   **Done updates the members:**
    *   members still selected keep their order;
    *   new ones are appended in the order picked;
    *   unselected ones are removed, as deselecting a chip does today.
*   **Dismissing changes nothing** in the form.
*   **Protocols sheets close when the app locks.** `ProtocolsLockGate` swaps
    only its own route, so a sheet above it would stay on screen, with Compound
    names, after the app re-locks. The picker, the Compound editor sheet and its
    archive dialog sit in `ProtocolsLockSheetGuard`
    (`protocols_lock_screen.dart`), which renders nothing while the lock state
    is locked or unavailable and removes its own route, so nested sheets each
    remove themselves.
*   **Selection color.** Cyan marks the selected filter chip only. Selected
    rows use a checkbox in the primary text color, and Done is a text button.
    This keeps DESIGN.md's rule of one cyan selection per screen.
*   **Performance at 200 Compounds:**
    *   filtering runs in memory on each keystroke, over a list read once when
        the sheet opens;
    *   the list is a lazily built `ListView`;
    *   each keystroke rebuilds the list within one frame (16 ms), checked by
        a widget test (file 10).

### D7. The Compound list and the Purpose manager (PR 1 and PR 2)

*   **Compound list:**
    *   **Filter row (PR 2):** under the search field, `PurposeFilterRow`, the
        same row as the picker. It reuses `FocusChip` (with `icon: null`) for
        each chip and copies only `_FocusChips`' row layout from the exercise
        picker.
    *   **Search:** matches the Compound's name, and from PR 2 the name of any
        of its active Purposes.
    *   **Sections:** Favorites, Recent and All compounds, each filtered.
    *   **Menu (PR 2):** the app bar gains an overflow menu with **Purposes**.
*   **Purpose manager (PR 2)** (`PurposeManagerScreen`) is modelled on
    `FocusManagerScreen`, without color:
    *   a reorderable list (long-press to drag);
    *   a menu on each row with **Rename** and **Archive**;
    *   **Add a Purpose**;
    *   a name dialog with inline errors for an empty or duplicate name.

    Archiving asks first, in a dialog titled with the Purpose's name alone
    ("Sleep") whose body reads "Archive this purpose? Compounds keep the tag; it
    stops showing." The name stays out of the question because a Purpose name is
    never combined with a verb in any string (file 36).
*   **Localization (PR 1).** Every string on the Compound list and in the
    editor sheet moves to `app_en.arb`. That includes the list's 15 hardcoded
    strings, such as "Search compounds", "New compound" and "Default unit".
    `doseUnitLabel` and `doseRouteLabel` stay as they are: they're shared with
    the log sheet, and moving them is a separate change.

### D8. Validation and golden vectors (PR 2)

*   **Purpose name.** A hard reject only, with no soft tier:
    *   **Empty:** a name that is empty after trimming is rejected,
        `purpose_name_required`.
    *   **Duplicate:** a name equal to another active Purpose's name, trimmed
        and case-insensitive, is rejected, `duplicate_purpose_name`.
    *   **Stored trimmed.** Archived Purposes don't count as duplicates.
*   **Purpose ids on a Compound write:**
    *   **Duplicates:** repeated ids are collapsed, keeping the first.
    *   **Agent writes:** an id that isn't an active Purpose is rejected,
        `purpose_not_found`. An archived id is rejected too, as an archived
        Focus id is on an Exercise write. So an Agent that reads a Compound
        tagged with an archived Purpose and writes the list back unchanged is
        rejected; it must drop the archived id or omit `purposeIds`.
    *   **App writes:** an archived id already on the Compound is kept, as
        D2 says.
*   **Golden vectors `m40-compound-purposes`** (the next free id: m40 at the
    time of writing, after m39), with a JSON Schema,
    registered in `ci.yml` and `ci-local.mjs` together. They pin:
    *   the starter set (the D3 table), which both sides need: Dart to seed,
        TypeScript to merge into Agent reads;
    *   `validatePurposeName` (empty, whitespace, a duplicate in another case,
        a duplicate of an archived name accepted);
    *   `normalizePurposeIds` (dedupe, order kept).

    Both cores run them. The seed tag table is Dart only and isn't a vector.

### D9. The Agent surface (PR 2)

Agents get the Purpose operations the app has.

| Operation | REST | MCP | Notes |
| :-------- | :--- | :-- | :---- |
| List Purposes | `GET /agent/protocols/purposes` (`listAgentPurposes`) | `agent_list_purposes` | `{purposes: [{id, name, sortOrder, starter, deletedAt}]}`. `includeArchived` defaults to false. The starter set is merged in for an account that has never synced it, as `listAgentFocuses` does; a stored row wins by id. |
| Write Purposes | `POST /agent/protocols/purposes/batch-write` (`batchWriteAgentPurposes`) | `agent_batch_write_purposes` | `{idempotencyKey, purposes: [{id, name, sortOrder, deletedAt?}]}`, 1–100 items. Creates, renames, reorders, and archives through `deletedAt`. The D8 name rules apply, checked against the merged starter set and stored rows. |
| Read a Compound | `listAgentCompounds` | `agent_list_compounds` | Items gain `purposeIds`, the stored list, which `fields` can select. The query gains `purpose` (an id), which filters on the stored list before paging. |
| Write a Compound | `batchWriteAgentCompounds` | `agent_batch_write_compounds` | Items gain an optional `purposeIds`. If omitted, the stored list is kept through carry-forward; `[]` clears it. `purpose_not_found` applies (D8). |

**Where the Compound check runs.** A new `createActivePurposeCheck`, modelled
on `createActiveFocusCheck`, loads the account's stored Purposes merged with
`STARTER_PURPOSES` once per request. It is passed into the Compound batch
write's store step, which rejects an inactive id with `purpose_not_found`.

The contract diff shows:

*   the two new operations;
*   `AgentPurpose`, `AgentPurposeListResponse` and the batch-write schemas;
*   `purposeIds` on `AgentCompound` and its batch-write item;
*   the `purpose` query parameter;
*   `purposes` in the two sync entity enums, those of `SyncPushRequest` and
    `SyncPulledChange` (D1).

`agent-client.ts`, the Dart API client and `api-operations.md` are
regenerated. The agent skill reference gains `list-purposes` and
`manage-purposes`.

## Alternatives Considered

### Alternative A: A single Category per Compound, defined by the app

The exercise model's shape: each Compound in exactly one app-defined Category.

*   **Pros**: a simpler picker (sections instead of a filter) and a familiar
    shape from Exercise Category.
*   **Cons**: a Compound often has several reasons (creatine for Performance
    and Cognition). An app-defined, fixed list is a classification the app
    owns, which is the thing the neutral-instrument rule forbids. "Category"
    also reads as what a substance *is*.
*   **Reason for Rejection**: it breaks the rule this spec only narrows, and a
    single value doesn't fit how people take Compounds.

### Alternative B: A join table `compound_purposes` as its own sync entity

One row per tag, like Protocol Members.

*   **Pros**: last-writer-wins per tag, so two devices tagging the same
    Compound with different Purposes at the same time both keep their tag.
*   **Cons**: a third new entity, with its own pull ordering, undo, erase and
    archive handling. The concurrent case it fixes means editing one
    Compound's tags on two devices within one sync interval.
*   **Reason for Rejection**: the Focus list on an Exercise is the precedent,
    and it has worked. A lost concurrent tag is visible, recoverable from the
    Activity Log, and fixed with one tap.

### Alternative C: Write the seed tags into the Compound rows (chosen)

Insert new seed rows with their tags, and backfill untouched rows once on
upgrade (D3).

*   **Pros**: the stored list is all there is. Sync, the Agent surface and the
    app read one field with no special rule, and the server needs no copy of
    the seed table.
*   **Cons**: on a signed-in device, the backfill writes a fresh timestamp on
    up to six existing rows per upgrading device. It can beat an edit made on
    another device that this device hasn't pulled yet (see
    [Risks](#risks-and-mitigations)).
*   **Reason for choosing**: the race is confined to the one-time backfill,
    is narrowed by running after a full pull, and its loser is recoverable.
    Alternative H's cost lasts forever.

### Alternative D: The user tags everything; the app ships no tags

*   **Pros**: keeps the neutral-instrument rule as written, and makes no
    suggestion of what a Compound is for.
*   **Cons**: the filter is empty until the user tags. A larger built-in
    library would arrive untagged, which is the case Purposes were asked for.
*   **Reason for Rejection**: the maintainer chose app tagging for the
    built-in Compounds. This spec limits it to the six OTC ones and leaves any
    wider tagging to the library spec.

### Alternative E: Keep the chip wall, and add a "New Compound" chip

*   **Pros**: the smallest change, and it fixes the inline-create problem.
*   **Cons**: it doesn't scale past a few dozen Compounds, has no search or
    filter, and leaves the Schedule editors pushing the chips off-screen.
*   **Reason for Rejection**: it fixes one of the nine problems.

### Alternative F: Auto-save an unfinished Protocol as a draft

Store the half-made Protocol instead of asking before discarding it.

*   **Pros**: nothing is ever lost, even when the app is killed.
*   **Cons**: a draft is a new persisted state. It has to be kept out of
    planning, reminders, Day Statuses, sync and the Agent surface, and it
    needs a place in the Protocol list.
*   **Reason for Rejection**: the inline-create path removes the main reason
    to leave the form, and a discard prompt covers accidental Back.

### Alternative G: One manager screen for Focuses and Purposes

Generalize `FocusManagerScreen` to manage either.

*   **Pros**: one screen to maintain.
*   **Cons**: Focuses have colors and their own entry points; Purposes live
    behind the Protocols lock and need their own copy; one parametrized screen
    couples the two domains' copy, keys and tests. The shared part is a
    reorderable list with rename and archive.
*   **Reason for Rejection**: the coupling costs more than the copied layout
    today. `FocusChip` is shared; only the row layout and the manager are
    copied. This is the third manager screen of this shape, after Category and
    Focus, so the next one should extract a shared screen instead.

### Alternative H: Read-through NULL for the seed tags

Leave `purposeIds` NULL until the first save, and read a NULL seed Compound as
tagged from a seed table held in both languages.

*   **Pros**: no write to existing rows on upgrade.
*   **Cons**: NULL and `[]` must stay distinct through sync, undo, the portable
    archive and every Agent write. An undo or an older client that sends NULL
    brings a removed tag back. The server needs the seed table, and the rule
    needs golden vectors and an exception in the sync rules.
*   **Reason for Rejection**: it can revive a removed tag, which Goal 4 rules
    out, and it adds a permanent special case to sync.

### Alternative I: Keep "No schedule" as the default, or ask for a time

Leave an added member on "No schedule", or prompt for a time when one is added.

*   **Pros**: no assumed time; nothing planned that the user didn't choose.
*   **Cons**: most Protocols are written in order to be reminded, so the user
    changes the default almost every time. A prompt adds a step for every
    Compound added.
*   **Reason for Rejection**: a visible default of every day at 9:00, one tap
    from "No schedule", costs less than either.

### Alternative J: Split this into two specs

One spec for the editor and picker, one for Purposes.

*   **Pros**: each spec is smaller to review.
*   **Cons**: the picker's filter, the editor sheet's chips and the list's
    filter are designed against both halves, so two specs would each
    reference the other. The project keeps related behavior changes in one
    spec.
*   **Reason for Rejection**: the work is split by feature into two PRs
    instead (see [Detailed Implementation Plan](#detailed-implementation-plan)),
    so each PR is reviewable on its own and PR 1 has no schema change.

### Alternative K: Search only Compound names

Let the Purpose filter alone narrow by Purpose.

*   **Pros**: one way to do one thing.
*   **Cons**: at 200 Compounds and up to 20 Purposes, typing "sle" is faster
    than scrolling the filter row.
*   **Reason for Rejection**: matching Purpose names costs one condition in an
    in-memory filter.

## Non-Functional Requirements

*   **Privacy.** Purposes are Protocols data:
    *   they are locked;
    *   they are left out of the CSV export;
    *   they are included in the portable archive;
    *   they are visible to the user's own Agent.

    The server stores and reads them, as it does all Protocols data. A Purpose
    name is never put in a notification or a log line, so reminders still name
    no Compound and no Purpose, and server logs record only entity names and
    counts, as for Compounds.
*   **Performance.**
    *   **The picker:** at 200 Compounds, each keystroke updates the list
        within one frame (16 ms), checked in a widget test with the frame
        timing budget. Rows are built lazily.
    *   **Inline create** writes one row locally and needs no network.
    *   **Saving the Protocol** does the same work as today.
    *   **The backfill** reads six rows and their Activity Log entries.
*   **Rollout and rollback.**
    *   **PR 1** changes no schema, sync shape or contract.
    *   **PR 2 is additive:**
        *   app schema 66 adds one table and one column with a default;
        *   the next free server migration (`0035` at the time of writing)
            adds one table;
        *   the sync protocol version stays 2.
    *   **Older clients** skip the `purposes` entity, and the server carries
        `purpose_ids` forward for them.
    *   **Rollback:** a reverted build leaves the table and column unused.
        Nothing reads or rewrites them.

## Risks and Mitigations

*   **App tags read as claims.** A shipped tag can read as "this works for
    sleep". *Mitigation:* tags only on the six OTC rows, a Purpose shown only
    as its name with no verb in any string (files 7 and 36), and any wider tagging
    left to the library spec.
*   **The backfill can beat an unpulled edit.** On a device with a sync
    account, the backfill writes a fresh stamp. An edit to the same seed row on
    another device that this device hasn't pulled yet loses. *Mitigation:* the
    backfill runs only after a Sync Run's pull has drained, which after the
    upgrade is a full pull (D1), so only an edit made between that pull and the
    push can
    lose; the loser is in the Activity Log. A signed-out device tags only rows
    that never synced, one second past each row's own stamp (D3), so it can't
    beat an edit made after this device seeded. An edit older than this
    device's seed already loses to the pending `otc_seed` entry a schema-65
    device stamped with the current time; that needs a device seeding on the
    old build after the edit, and its loser is in the Activity Log.
*   **Concurrent tag edits on two devices.** The tags are one field, so one
    device's list wins. *Mitigation:* the Activity Log keeps the loser
    (Alternative B records why per-tag rows aren't worth it).
*   **A skipped entity before the upgrade.** An older build advances its pull
    cursor past `purposes` changes. *Mitigation:* the `from < 66` step clears
    the pull cursor (D1).
*   **Privacy.** Purpose names are sensitive by association. *Mitigation:* the
    same lock, export and log rules as Compounds (NFRs).
*   **Scale.** The picker and the list filter in memory. *Mitigation:* the
    200-Compound frame test; a library past that size is the library spec's
    concern.

--------------------------------------------------------------------------------

## Detailed Implementation Plan

This lands in two implementation PRs, both against `main`, after this spec
merges. They are split by feature, not by layer, so each is reviewable and
usable on its own:

*   **PR 1, building a Protocol:** Compound edit and archive, the
    archived-member save fix, the reshaped Protocol editor, the picker with
    search and inline create but no Purpose filter, and the copy moved to the
    ARB. No schema, sync or contract change.
*   **PR 2, Purposes end to end:** the schema, sync, seeds and backfill, the
    golden vectors, the Agent surface, the filter rows, the editor sheet's
    Purpose chips and the Purpose manager.

PR 1 sets this spec's Status to **Approved; PR 1 of 2 built** in its header and
the SITEMAP. PR 2 sets it to **Current**.

**Numbers this spec claims.** App schema version 66, golden-vector id `m40` and
server migration `0035` are the next free ones at the time of writing (`main`
ends at schema 65, vector m39 and migration 0034). Another spec may take one
first. If it does, PR 2 takes the next free number and corrects every line of
this spec that names it, in the same pull request.

Each PR section below starts with its file table and the Verification Plan items
it must pass. The numbered file entries after the table give the detail, and
point back to the Technical Plan sections (D1–D9).

### PR 1: Building a Protocol

| # | Files | Change |
|---|---|---|
| 1 | `apps/mobile/lib/domain/protocols/protocols.dart` | Modify |
| 2 | `apps/mobile/lib/data/repositories/training_repositories.dart` | Modify |
| 3 | `apps/mobile/lib/features/protocols/controllers/protocols_day_controller.dart` | Modify |
| 4 | `apps/mobile/lib/features/protocols/widgets/compound_picker_sheet.dart` | Create |
| 5 | `apps/mobile/lib/features/protocols/widgets/compound_list_screen.dart` | Modify |
| 6 | `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart` | Modify |
| 7 | `apps/mobile/lib/l10n/app_en.arb` and the generated l10n files | Modify; Regenerate |
| 8 | `DESIGN.md` | Modify |
| 9 | `CHANGELOG.md` | Modify |
| 10 | Tests for PR 1 | Modify, Create |

**Verification Plan items:** V1 (the `mobile` job), V5 (file 10's tests) and V6
(CUJs 1, 3, 5 and 7, without the Purpose filter). V2, V3 and V4 don't apply:
this PR changes no golden vectors, contract or sync shape.

#### 1. `apps/mobile/lib/domain/protocols/protocols.dart` (Modify)

*   **Type / Scope**: domain records.
*   **Proposed Changes**: `CompoundScheduleOptionRecord` gains `isArchived`
    (D4), default false.

#### 2. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

*   **Type / Scope**: `ProtocolsRepository`.
*   **Proposed Changes**:
    *   **The archived-member rule (D4):** `_editProtocol` loads the
        Protocol's live member Compound ids before the check, and calls
        `_requireActiveCompoundRows` only for ids not in that set. Rows for
        the rest are loaded without the active filter. `_createProtocol` is
        unchanged.
    *   **A read that includes archived Compounds:** a new
        `Stream<List<CompoundScheduleOptionRecord>> watchCompoundsByIds(Set<String>
        ids)`, returning archived Compounds too, with `isArchived` set.
        `watchCompoundNamesByIds` is unchanged.
    *   **The no-op edit (D4):** `editCompound` returns `Future<String?>`. When
        the draft's fields all equal the stored row, `_editCompound` writes
        nothing and `editCompound` returns null. Update its callers.

#### 3. `apps/mobile/lib/features/protocols/controllers/protocols_day_controller.dart` (Modify)

*   **Type / Scope**: Riverpod.
*   **Proposed Changes**:
    *   **Provider:** `compoundsByIdsProvider`, an autoDispose
        `StreamProvider.family` over `watchCompoundsByIds`, keyed by the same
        request type `watchCompoundNamesByIds`' provider uses.
    *   **Controller methods:**
        *   `editCompound(String id, CompoundDraft draft)` and
            `archiveCompound(String id)`, forwarding to the repository;
        *   `Future<int> countProtocolsWithCompound(String compoundId)`, over
            `listProtocolSummaries()` (D4);
        *   `Future<Map<String, ({double amount, DoseUnit unit})>>
            latestDoseAmounts(Set<String> compoundIds)`, built from
            `lastDoseFor` for each id, skipping ids with no Dose.
    *   **Removed:** `compoundScheduleOptionListProvider` and the repository's
        `watchCompoundScheduleOptions`. The chip wall was their only reader;
        the form now reads Compounds from `compoundsByIdsProvider` alone.

#### 4. `apps/mobile/lib/features/protocols/widgets/compound_picker_sheet.dart` (Create)

*   **Type / Scope**: a new sheet.
*   **Proposed Changes**: `Future<List<String>?> showCompoundPickerSheet(
    BuildContext context, {required List<String> selectedIds})`, laid out as
    D6 describes, without the Purpose filter row and with name-only search.
    *   It reads active Compounds once per open from the existing Compound list
        provider, with its Favorites and Recent. It invalidates both providers
        first: from the Protocol editor nothing listens to them between opens,
        so Riverpod has paused them, and `.future` alone would answer with the
        list from before any write made since.
    *   Keys for the search field, each row, the Create row and Done.
    *   The Create row opens `CompoundEditorSheet(initialName:)` and awaits
        the new id.

#### 5. `apps/mobile/lib/features/protocols/widgets/compound_list_screen.dart` (Modify)

*   **Type / Scope**: the Compound list and the Compound editor sheet.
*   **Proposed Changes**:
    *   **List:** a long-press on a row opens `CompoundEditorSheet(compound:)`
        directly, and the row gets a `Semantics` custom action **Edit**.
    *   **`CompoundEditorSheet`:**
        *   it gains optional `compound` and `initialName`, and returns the
            saved id;
        *   it adds inline name and strength errors, and Archive with the D4
            dialog, which uses `countProtocolsWithCompound`.
    *   **Copy:** every string listed in D7 moves to the ARB.

#### 6. `apps/mobile/lib/features/protocols/widgets/protocol_screen.dart` (Modify)

*   **Type / Scope**: the Protocol editor.
*   **Proposed Changes**:
    *   **New order:** reorder `build()` to D5's order.
    *   **Member rows:** replace the chip `Wrap` with member rows and **Add
        Compounds**, which calls `showCompoundPickerSheet` with the members
        whose Compounds are active. On a result, the form keeps members whose
        Compounds are archived in their place, applies the result as D6 says
        through `_toggleCompound`'s add and remove logic, and appends nothing
        for them.
    *   **Member names:** watch `compoundsByIdsProvider` for the member ids,
        and show **Archived** when `isArchived`. This is the form's only source
        of a Compound: a row's name is blank until the lookup answers.
    *   **Schedule editor:** show `_ScheduleEditor` in a modal bottom sheet
        through a `StatefulBuilder` that also calls the form's `setState`.
    *   **Summaries:** a public `ScheduleSummaryInput` value record (choice,
        weekdays or interval, times, count per day, amount, unit) built from
        `_ScheduleFieldState`, and `String protocolScheduleSummary(
        AppLocalizations l10n, ScheduleSummaryInput input, {required
        MaterialLocalizations material, required String localeName, bool
        alwaysUse24HourFormat = false})`, following the D5 table. Callers pass
        `MediaQuery.alwaysUse24HourFormatOf(context)`, the device's time
        format. The amount is nullable.
    *   **The When section:** a `_PeriodSection` that is collapsed to a
        summary and expands in place. It expands when `_showErrors` is set and
        a period issue exists.
    *   **Added-member default (D5):** a new factory
        `_ScheduleFieldState.forNewMember(CompoundScheduleOptionRecord
        compound, ({double amount, DoseUnit unit})? lastDose, {required
        ProtocolDayDate protocolStart})`, the start being the every-N anchor. Only the
        picker-result path calls it: before applying a result, the form awaits
        `latestDoseAmounts` for the ids being added, then builds their fields
        with `forNewMember`. `_fieldFor` stays synchronous and keeps calling
        `fromVersion` for existing members.
    *   **Unsaved changes:** add `_FormSnapshot`, a value record of D5's fields
        with `==`. It is taken at the end of `initState`. A `PopScope` with
        `canPop: _snapshot() == _initialSnapshot || _saved` shows the discard
        dialog.
    *   **A failed Archive:** it fails the way Delete does. A `StateError` means
        the Protocol was already archived on another device, so the editor
        closes. Any other error re-enables the buttons and shows
        `protocolEditorArchiveFailed` ("Could not archive the Protocol:
        {error}"), so Back still reaches the discard dialog.
    *   **Key changes:** remove `compoundChipKey`, and add keys for member
        rows, Add Compounds, the period summary and the dialog buttons.

#### 7. `apps/mobile/lib/l10n/app_en.arb` (Modify) and generated l10n files (Regenerate)

*   **Type / Scope**: copy.
*   **Proposed Changes**: every new string from D4 to D7 for PR 1, and the
    moved hardcoded strings. Counts are ICU plurals. Regenerate with `flutter
    gen-l10n`.

#### 8. `DESIGN.md` (Modify)

*   **Type / Scope**: design system prose. It adds no token.
*   **Proposed Changes**: under Components, add **Picker sheet:** nearly full
    height, search then list, with checkboxes in the primary text color and a
    Done text button with a count, so that a selected filter chip is the only
    cyan selection on screen.

#### 9. `CHANGELOG.md` (Modify)

*   **Type / Scope**: release notes.
*   **Proposed Changes**: under `[Unreleased]`:
    *   **Added:** edit and archive a Compound; create a Compound from the
        Protocol editor's picker.
    *   **Changed:** the Protocol editor puts Compounds first, picks them from
        a searchable sheet, and asks before discarding unsaved changes; an
        added Compound starts every day at 9:00.
    *   **Fixed:** a Protocol whose Compound was archived can be saved again.

#### 10. Tests for PR 1 (Modify, Create)

*   **`apps/mobile/test/features/protocols/protocols_repository_test.dart`:**
    *   editing a Protocol with a member whose Compound is archived succeeds;
        adding an archived Compound is rejected;
    *   `watchCompoundsByIds` returns archived Compounds with `isArchived`;
    *   an unchanged `editCompound` writes nothing and returns null.
*   **`apps/mobile/test/features/protocols/compound_picker_sheet_test.dart`
    (Create):**
    *   the selection kept across search;
    *   Done's count;
    *   the Create row shown only with no exact match;
    *   the result order;
    *   dismissing returns null;
    *   200 Compounds: each keystroke rebuilds within 16 ms, under the frame
        timing budget the other screen budgets use.
*   **`apps/mobile/test/features/protocols/protocol_screen_test.dart`:**
    *   **CUJ 1, without the filter:** inline create, the name kept, and the
        summary rows, including "Add an amount";
    *   **CUJ 2:** one sheet at a time;
    *   **CUJ 3:** the discard dialog on a dirty form, and none on a clean
        one;
    *   **CUJ 7:** the archived member's row, the picker result keeping it,
        and save succeeds;
    *   **the added-member default,** with and without a last Dose, and an
        existing member with no Schedule Version keeping "No schedule";
    *   **the period section:** its summary texts, and expanding on an issue.
*   **`apps/mobile/test/features/protocols/protocol_schedule_summary_test.dart`
    (Create):** every row of the D5 summary table, in a 12-hour and a
    24-hour locale.
*   **`apps/mobile/test/features/protocols/compound_list_screen_test.dart`:**
    *   a long-press opens the editor, and a tap still opens the log sheet;
    *   the archive dialog's two texts;
    *   inline name and strength errors;
    *   no hardcoded English: a widget test with a test-only
        `AppLocalizations` delegate that prefixes every string finds no
        visible text without the prefix.
*   **`apps/mobile/test/features/protocols/protocol_plan_reopen_test.dart`:**
    kill and reopen mid-edit. An unsaved Protocol isn't persisted, and a
    Compound created inline is.
*   **Accessibility:** the existing app-shell accessibility checks run on the
    picker, the editor sheet and the reshaped Protocol editor in both themes,
    at 320 dp and 1.3× text.

### PR 2: Purposes end to end

| # | Files | Change |
|---|---|---|
| 11 | `apps/mobile/lib/domain/protocols/compound_purposes.dart` | Create |
| 12 | `apps/mobile/lib/domain/protocols/protocols.dart` | Modify |
| 13 | `apps/mobile/lib/data/local/app_database.dart` and the Drift schema snapshots | Modify; Regenerate |
| 14 | `apps/mobile/lib/data/repositories/purpose_repository.dart`; `training_repositories.dart` and `apps/mobile/lib/features/activity/undo_conflict_message.dart` | Create; Modify |
| 15 | `apps/mobile/lib/data/repositories/training_repositories.dart` and `plan_sync_repository.dart` | Modify |
| 16 | `apps/mobile/lib/data/seeds/otc_compound_seed.dart` | Modify |
| 17 | `apps/mobile/lib/features/sync/repositories/sync_repository.dart` and `services/sync_cycle_runner.dart` | Modify |
| 18 | `apps/mobile/lib/features/activity/repositories/activity_feed_repository.dart` | Modify |
| 19 | `apps/mobile/lib/data/repositories/portable_archive_repository.dart` | Modify |
| 20 | `apps/mobile/lib/features/protocols/controllers/protocols_day_controller.dart` | Modify |
| 21 | `packages/golden-vectors/vectors/m40-compound-purposes.json` and `m40-compound-purposes.schema.json` | Create |
| 22 | `apps/mobile/test/domain/compound_purposes_golden_test.dart` and `apps/server/test/compound-purposes.golden.test.mjs` | Create |
| 23 | `.github/workflows/ci.yml`, `tools/ci-local.mjs` and `apps/server/package.json` | Modify |
| 24 | `apps/server/src/compound-purposes.ts` | Create |
| 25 | `apps/server/src/db/schema.ts` and `apps/server/drizzle/0035_purposes.sql` | Modify, Create |
| 26 | `apps/server/src/sync.ts` | Modify |
| 27 | `apps/server/src/app.ts`, `agent-activity.ts`, `index.ts` and `observability.ts` | Modify |
| 28 | `apps/server/src/agent-protocols.ts` | Modify |
| 29 | `apps/server/src/agent-mcp.ts` | Modify |
| 30 | Generated contract files | Regenerate |
| 31 | `packages/contract/src/agent-skill-reference.ts`, `agent-skills/perennia/scripts/prn-agent.mjs`, `prn-code.mjs` and `SKILL.md` | Modify |
| 32 | `apps/mobile/lib/features/protocols/widgets/purpose_filter_row.dart` | Create |
| 33 | `apps/mobile/lib/features/protocols/widgets/compound_picker_sheet.dart` | Modify |
| 34 | `apps/mobile/lib/features/protocols/widgets/compound_list_screen.dart` | Modify |
| 35 | `apps/mobile/lib/features/protocols/widgets/purpose_manager_screen.dart` | Create |
| 36 | `apps/mobile/lib/l10n/app_en.arb` and the generated l10n files | Modify; Regenerate |
| 37 | `DESIGN.md` | Modify |
| 38 | `CONTEXT.md` | Modify |
| 39 | `docs/designs/protocol-schedules-and-reminders.md` | Modify |
| 40 | `CHANGELOG.md` | Modify |
| 41 | Tests for PR 2 | Modify, Create |

**Verification Plan items:** V1 (the `mobile`, `golden`, `contract`, `js` and
`sync` jobs), V2, V3, V4, V5 (file 41's tests) and V6 (CUJs 1, 5 and 8).

#### 11. `apps/mobile/lib/domain/protocols/compound_purposes.dart` (Create)

*   **Type / Scope**: Dart domain core, no Flutter imports.
*   **Proposed Changes**:
    *   `const starterPurposes`: a list of `(id, name, sortOrder)`, from the D3
        table.
    *   `const seedCompoundPurposeIds`: `Map<String, List<String>>`, from the
        D3 seed tag table.
    *   `List<String> normalizePurposeIds(Iterable<String> ids)`: dedupe,
        keeping the first occurrence and the order.
    *   `String validatePurposeName(String name, Iterable<String>
        activeNamesExcludingSelf)`. It returns the trimmed name, and throws
        `PurposeNameException` with code `purpose_name_required` or
        `duplicate_purpose_name`.
    *   `String purposeNameKey(String name)`: what two names are compared by,
        trimmed and lowercased. `_purposeUndoConflicts` (file 14) shares it.
    *   `compoundSeedTimestamp`: the fixed seed timestamp `DateTime.utc(2026,
        10, 24)` (D3), for the Purpose and OTC Compound seeds.
    *   A docstring stating the narrowed neutral-instrument rule and that the
        seed tag table covers OTC Compounds only.

#### 12. `apps/mobile/lib/domain/protocols/protocols.dart` (Modify)

*   **Type / Scope**: domain records.
*   **Proposed Changes**:
    *   **`PurposeRecord`:** `id`, `name`, `sortOrder`, `updatedAt`,
        `deletedAt`.
    *   **`CompoundRecord`:** gains `purposeIds`, the stored list.
    *   **`CompoundScheduleOptionRecord`:** gains `purposeIds`, for the picker's
        row of a Compound it just created (file 33).
    *   **`CompoundDraft`:** gains `List<String>? purposeIds`. Null means leave
        unchanged; a list is stored as given after `normalizePurposeIds`.

#### 13. `apps/mobile/lib/data/local/app_database.dart` (Modify), and the Drift schema snapshots (Regenerate)

*   **Type / Scope**: Drift schema.
*   **Proposed Changes**:
    *   **Table `Purposes`** as in D1, with `AppDatabase.purposesTable =
        'purposes'` added to `tableNames`.
    *   **Compounds:** `Compounds.purposeIds`,
        `text().withDefault(const Constant('[]'))()`.
    *   **Schema version:** `schemaVersion` 66, with step `from < 66`, which
        creates `purposes` if it is missing, adds `compounds.purpose_ids` if
        missing (default `'[]'`), and runs `UPDATE sync_states SET
        pull_cursor = NULL` (D1).
    *   **Comments:** update the Compounds table comment that says the app
        never categorizes, to the narrowed rule.
    *   **Snapshots:** dump the version 66 schema and regenerate the schema
        test helpers with the commands in `docs/releasing.md`; never edit them
        by hand.

#### 14. `apps/mobile/lib/data/repositories/purpose_repository.dart` (Create), `training_repositories.dart` and `features/activity/undo_conflict_message.dart` (Modify)

*   **Type / Scope**: a repository, a `part of training_repositories.dart`,
    modelled on `focus_repository.dart`.
*   **Proposed Changes**:
    *   **Reads:** `watchActive()` and `listActive()` (ordered by `sortOrder`,
        then name).
    *   **Writes:**
        *   `create(name)` appends at the end of the order;
        *   `rename(id, name)`, `reorder(List<String> ids)` and `archive(id)`.
        *   Each is one Activity Log batch with actor `manual` by default.
        *   Names are checked by `validatePurposeName`.
    *   **Seeding:** `_seedStarterPurposes(context)` inserts absent starter ids
        with the fixed seed timestamp.
    *   **Images:** `_purposeImage` with keys `id`, `name`, `sort_order`,
        `updated_at`, `deleted_at`, and `_purposeCompanionFromImage`.
    *   **Undo into a duplicate name:** an undo that would bring back a name
        another active Purpose now holds, by restoring an archived Purpose or
        reversing a rename, is reported as not applied. `ActivityLogUndoConflictReason`
        gains `duplicatePurposeName`, reported by `_purposeUndoConflicts(entries)`
        next to `_mealDependentUndoConflicts` in `training_repositories.dart`.
        `undoConflictMessage` gets a branch for it, with its own ARB string
        (file 36).

#### 15. `apps/mobile/lib/data/repositories/training_repositories.dart` and `plan_sync_repository.dart` (Modify)

*   **Type / Scope**: `ProtocolsRepository`, sync images, erase and undo.
*   **Proposed Changes**:
    *   **Purposes:** expose the new repository as `ProtocolsRepository.purposes`.
    *   **Seeding (D3):** `ensureOtcLibrarySeeded` calls `_seedStarterPurposes`
        before the early return for an empty OTC source.
        `_ensureOtcLibrarySeeded` inserts each absent row with
        `purposeIds` from `seedCompoundPurposeIds`, stamped with the fixed seed
        timestamp `2026-10-24T00:00:00Z` instead of `context.timestamp`.
    *   **Backfill (D3):** a new
        `Future<void> backfillSeedPurposes({bool onlyNeverSynced = false})` with
        actor `otc_purpose_seed`, applying the untouched test to each seed
        row in one transaction. `ProtocolDayController.ensureOtcLibrarySeeded`
        calls it with `onlyNeverSynced: true` when the device is signed out,
        which limits it to rows with `syncPreviouslySynced` false and stamps
        each one second past its own `updatedAt` (file 20), and
        `RepositorySyncCycleRunner` calls it with the current time when it has
        an account (file 17).
    *   **Compound writes:**
        *   `_createCompound` stores `purposeIds`, as `'[]'` when the draft
            gives none.
        *   `_editCompound` writes `purposeIds` when the draft carries a list,
            and includes it in the no-op comparison (D4).
    *   **Reading:** `_compoundFromRow` decodes `purposeIds`; a string that
        isn't a JSON array decodes to no tags (D2).
    *   **Sync and undo:**
        *   `_compoundImage` adds `purpose_ids`, the stored JSON string.
        *   `_compoundCompanionFromImage` and `_compoundSyncCompanionFromImage`
            read it with `_imageNonNullStringIfPresent`, because the column is
            NOT NULL.
        *   `_activityLaterAddedKeyDefaults[compounds]` gains
            `{'purpose_ids': '[]'}`.
    *   **Erase and pulls:**
        *   `eraseTableNames` gains `purposes`.
        *   `_seedOwnedIdsForErase` gains the starter Purpose ids.
        *   `applyPlanSyncImage`, the generic path Focus uses (D1), accepts
            `purposes`: the switches in `plan_sync_repository.dart` gain
            `purposes` cases. `ProtocolsRepository._syncEntityTables` doesn't
            change, because Purposes don't go through its `applySyncImage`.
        *   `_currentImageFor` and the write-back switch gain `purposes` cases.

#### 16. `apps/mobile/lib/data/seeds/otc_compound_seed.dart` (Modify)

*   **Type / Scope**: seed source.
*   **Proposed Changes**: rewrite the class docstring to the narrowed rule. It
    must say that the seed still has no type or legality field, and that its
    Purpose tags live in `compound_purposes.dart`. The rows don't change.

#### 17. `apps/mobile/lib/features/sync/repositories/sync_repository.dart` and `services/sync_cycle_runner.dart` (Modify)

*   **Type / Scope**: sync client.
*   **Proposed Changes**:
    *   **Sync entity:** add `_purposeSyncEntity`, a `_PlanSyncEntity` with
        local and remote `AppDatabase.purposesTable`, on the path
        `_focusSyncEntity` uses, and add the table to the outbound entity list
        next to `focusesTable`.
    *   **Push:** push it before Compounds, through
        `_pushPendingPlanEntityWithClient`.
    *   **Apply order:** `_syncApplyOrder` gives `purposesTable` 0, next to
        Focus.
    *   **Backfill (D3):** add `Future<void> backfillSeedPurposes()` to
        `SyncCycleRepository`, with `SyncRepository` forwarding to
        `ProtocolsRepository.backfillSeedPurposes()`.
        `RepositorySyncCycleRunner.run` decides a Sync Run's success, so it
        makes the call: after the inner pull loop has drained and before
        `hasPendingChanges()`, once per drain pass. It is a no-op after the
        first. Its writes count as pending on a pass with no progress, which
        the runner's limit of two no-progress passes tolerates, because the
        next pass pushes them.
    *   **A dropped key (D1):** `_applyPulledCompoundChange`, when last-writer-
        wins doesn't apply the change, restores `purpose_ids` on a row an older
        build applied at that same version.

#### 18. `apps/mobile/lib/features/activity/repositories/activity_feed_repository.dart` (Modify)

*   **Type / Scope**: the Activity feed label.
*   **Proposed Changes**: `_entityLabel` maps `AppDatabase.purposesTable` to
    the literal `'purpose'`, as it does every other entity.

#### 19. `apps/mobile/lib/data/repositories/portable_archive_repository.dart` (Modify)

*   **Type / Scope**: the portable archive.
*   **Proposed Changes**:
    *   **Export and import:** add a `purposes` entity before `compounds`, with
        merge import by id and last-writer-wins.
    *   **Older archives:** an archive with `archiveSchemaVersion < 66` has no
        `purposes` file and skips it, as `< 59` does for Focuses.
    *   **Compound rows:** `CompoundRow.fromJson` throws on a missing non-null
        key, so a `_PortableCompoundRow`, shaped like `_PortableFocusRow`,
        defaults `purposeIds` to `'[]'` on parse and records whether the key was
        present. It upserts through a companion that leaves the column absent
        when the key wasn't, so a version-65 archive row can never erase newer
        tags.

#### 20. `apps/mobile/lib/features/protocols/controllers/protocols_day_controller.dart` (Modify)

*   **Type / Scope**: Riverpod.
*   **Proposed Changes**:
    *   **Provider:** `activePurposesProvider`, a
        `StreamProvider<List<PurposeRecord>>`.
    *   **Controller methods:** `createPurpose`, `renamePurpose`,
        `reorderPurposes` and `archivePurpose`. `createCompound` and
        `editCompound` take the draft with `purposeIds`.
    *   **`ensureOtcLibrarySeeded`:** awaits the repository seed, reads
        `authControllerProvider.future`, and calls
        `backfillSeedPurposes(onlyNeverSynced: true)` only when the user isn't
        signed in. If the auth read throws, it skips the
        backfill, because tagging before a pull could beat an edit made
        elsewhere and the next open retries (D3).

#### 21. `packages/golden-vectors/vectors/m40-compound-purposes.json` and `m40-compound-purposes.schema.json` (Create)

*   **Type / Scope**: golden vectors.
*   **Proposed Changes**: the cases listed in D8, under three operations:
    `starterPurposes`, `validatePurposeName` and `normalizePurposeIds`. The
    `starterPurposes` case's expected output is the D3 table. The vectors
    README index gains the file.

#### 22. `apps/mobile/test/domain/compound_purposes_golden_test.dart` and `apps/server/test/compound-purposes.golden.test.mjs` (Create)

*   **Type / Scope**: golden runners.
*   **Proposed Changes**: run every m40 case against the Dart and TypeScript
    cores, as `metric_trend_golden_test.dart` and `metric-trend.golden.test.mjs`
    do.

#### 23. `.github/workflows/ci.yml`, `tools/ci-local.mjs` and `apps/server/package.json` (Modify)

*   **Type / Scope**: the gate.
*   **Proposed Changes**:
    *   append `test/compound-purposes.golden.test.mjs` to the server's
        `test:golden-vectors` script;
    *   add `apps/server/src/compound-purposes.ts` and
        `apps/server/test/compound-purposes.golden.test.mjs` to the
        `golden_vectors` path filter, in the same commit in both `ci.yml` and
        `ci-local.mjs`;
    *   register the `compound-purposes` domain with its runner in
        `DOMAINS_OWNED_ELSEWHERE` in
        `apps/server/test/agent-validation.golden.test.mjs` and in
        `apps/mobile/test/domain/golden_vector_ownership_test.dart`, which fail
        on a vector no runner claims.

#### 24. `apps/server/src/compound-purposes.ts` (Create)

*   **Type / Scope**: server core, the mirror of file 11.
*   **Proposed Changes**: `STARTER_PURPOSES`, `purposeNameKey`,
    `normalizePurposeIds` and `validatePurposeName`, which throws
    `PurposeNameError` with the same codes. There is no seed tag table on the
    server.

#### 25. `apps/server/src/db/schema.ts` and `apps/server/drizzle/0035_purposes.sql` (Modify, Create)

*   **Type / Scope**: Postgres schema.
*   **Proposed Changes**:
    *   **Table `purposes`:** shaped like `focuses` without `color_hex`, with
        primary key `(user_id, id)` and index `purposes_user_updated_at_index`.
    *   **The migration** and its `meta` snapshot are generated by `pnpm
        --filter @perennia/server db:generate --name purposes`, never
        hand-edited.

#### 26. `apps/server/src/sync.ts` (Modify)

*   **Type / Scope**: sync server.
*   **Proposed Changes**:
    *   **Entity:** add `PURPOSES_SYNC_ENTITY = "purposes"` to the entity
        lists where `FOCUSES_SYNC_ENTITY` appears, the `AccountKeyedSyncTable`
        union and the push dispatch.
    *   **Push:** `SyncStore.pushPurposes` and an exported
        `pushPurposesInTransaction`, modelled on `pushFocuses` and
        `pushFocusesInTransaction`.
    *   **Pull:** add the table to the pull cursor query and `baseRows`, with
        sort rank 1.5. The entity has no pull parent references.
    *   **Carry-forward:** `SYNC_CARRY_FORWARD_PAYLOAD_KEYS` gains
        `[COMPOUNDS_SYNC_ENTITY]: ["is_favorite", "purpose_ids"]`, with a
        comment that it is a JSON-encoded string array like `focus_ids`.

#### 27. `apps/server/src/app.ts`, `agent-activity.ts`, `index.ts` and `observability.ts` (Modify)

*   **Type / Scope**: server routing and registries.
*   **Proposed Changes**:
    *   **`app.ts`:** a `PURPOSES_SYNC_ENTITY` case in the sync push switch,
        next to `FOCUSES_SYNC_ENTITY`, calling `syncStore.pushPurposes`; and
        the two Purpose routes, registered next to the Compound routes.
    *   **`agent-activity.ts`:** a `PURPOSES_SYNC_ENTITY` entry pushing through
        `pushPurposesInTransaction`, so Agent Purpose writes are undoable.
    *   **`index.ts`:** re-export the new entity constant and push function.
    *   **`observability.ts`:** add `purpose`, `purposes`, `purposeid`,
        `purposeids` and `purposename` to the scrubber's denylist of normalized
        key names, in the Protocols block, so a Purpose name is never logged.

#### 28. `apps/server/src/agent-protocols.ts` (Modify)

*   **Type / Scope**: the Agent Protocols surface.
*   **Proposed Changes**:
    *   **Purpose schemas:** `AgentPurposeSchema`, `AgentPurposeListQuerySchema`
        (`includeArchived`), `AgentPurposeListResponseSchema`, and the
        batch-write request, item and response schemas, shaped as D9 says.
    *   **Purpose routes:** `listAgentPurposes` merges `STARTER_PURPOSES` with
        the user's rows (a user row wins by id) and drops archived rows unless
        `includeArchived` is `true`, a `"true"`/`"false"` string because
        `z.coerce.boolean` reads `"false"` as true. `batchWriteAgentPurposes`
        validates names against the merged active names after the batch is
        applied in order, then writes through `pushPurposesInTransaction`. A
        first write to a starter with no stored row logs that starter as its
        before image, so undo restores it instead of tombstoning it.
    *   **`createActivePurposeCheck`:** modelled on `createActiveFocusCheck`;
        loads stored rows merged with `STARTER_PURPOSES` once per request.
    *   **Compound read and write:**
        *   `AgentCompoundSchema` and `AGENT_COMPOUND_FIELDS` gain
            `purposeIds`, parsed from the stored `purpose_ids` with
            `parseJsonStringArray`.
        *   `AgentCompoundListQuerySchema` gains `purpose`, which filters on
            the stored list before paging.
        *   `AgentCompoundBatchWriteCompoundSchema` gains optional
            `purposeIds`.
        *   `prepareAgentCompoundBatchWrite` writes `purpose_ids` with
            `JSON.stringify` only when it is given, after
            `normalizePurposeIds`. The store step rejects an id that fails
            `createActivePurposeCheck` with `purpose_not_found`, in `finalize`,
            so a replay of a recorded batch still returns its receipt after
            that Purpose is archived.
        *   The Compound group's `laterAddedKeyDefaults` gives a before image
            `purpose_ids: '[]'` when the write sets the key and the stored row
            lacks it (D2).
    *   **The Protocol batch write** is unchanged (D4).

#### 29. `apps/server/src/agent-mcp.ts` (Modify)

*   **Type / Scope**: MCP tools.
*   **Proposed Changes**: add `agent_list_purposes` and
    `agent_batch_write_purposes`, with the same helpers as REST. The Compound
    tools gain the new fields through their shared schemas.

#### 30. Generated contract files (Regenerate)

*   **Type / Scope**: `packages/contract/openapi.json`,
    `packages/contract/src/agent-client.ts`,
    `apps/mobile/lib/api/perennia_api_client.dart` and
    `agent-skills/perennia/references/api-operations.md`.
*   **Proposed Changes**: regenerate with `pnpm --filter @perennia/contract
    generate`. They are never edited by hand.

#### 31. `packages/contract/src/agent-skill-reference.ts`, `agent-skills/perennia/scripts/prn-agent.mjs`, `prn-code.mjs` and `SKILL.md` (Modify)

*   **Type / Scope**: the agent skill.
*   **Proposed Changes**: add the commands `list-purposes` and
    `manage-purposes` to the skill reference, the matching commands to
    `prn-agent.mjs`, next to `list-compounds`, the client methods
    `listAgentPurposes` and `batchWriteAgentPurposes` to `prn-code.mjs`, and
    the command examples to `SKILL.md`.

#### 32. `apps/mobile/lib/features/protocols/widgets/purpose_filter_row.dart` (Create)

*   **Type / Scope**: a shared widget.
*   **Proposed Changes**:
    *   **`PurposeFilterRow`** takes `purposes`, `selectedId` (null means All)
        and `onSelected`.
    *   **Its chips** are `FocusChip(icon: null)` from `focus_visuals.dart`.
    *   **Its layout** copies the `_FocusChips` row from
        `exercise_catalog_picker.dart`: a `Semantics` label, then a sideways
        `SingleChildScrollView` holding All followed by one chip per Purpose.
    *   Callers omit it when there are no active Purposes, because they also
        drop its spacing.
    *   The file also holds `compoundMatchesFilter` and
        `compoundFilterEmptyMessage`, the one search-and-filter rule and empty
        message shared by the list and the picker.

#### 33. `apps/mobile/lib/features/protocols/widgets/compound_picker_sheet.dart` (Modify)

*   **Type / Scope**: the picker from file 4.
*   **Proposed Changes**: add `PurposeFilterRow` under search, match active
    Purpose names in search, and pass the active filter to the Create row as
    `CompoundEditorSheet(initialPurposeIds:)`. The row for a Compound created
    here reads its tags from `CompoundScheduleOptionRecord.purposeIds` (files 12
    and 15), because the sheet keeps the list it read when it opened. A filter
    with nothing to show and no search says "No compounds with this purpose.",
    in the list too. It filters with `compoundMatchesFilter` and picks its empty
    message with `compoundFilterEmptyMessage`, both from file 32.

#### 34. `apps/mobile/lib/features/protocols/widgets/compound_list_screen.dart` (Modify)

*   **Type / Scope**: the Compound list and the Compound editor sheet.
*   **Proposed Changes**:
    *   **List:** add `PurposeFilterRow` under search, make search match active
        Purpose names, and add the app bar overflow menu with **Purposes**,
        which pushes `PurposeManagerScreen`. It filters with
        `compoundMatchesFilter` and picks its empty message with
        `compoundFilterEmptyMessage`, both from file 32.
    *   **`CompoundEditorSheet`:** gains `initialPurposeIds` and a Purposes
        chip wrap (`FocusChip(icon: null)`), keeping any archived id attached.
    *   **Docstrings:** update the class docstrings to the narrowed rule.

#### 35. `apps/mobile/lib/features/protocols/widgets/purpose_manager_screen.dart` (Create)

*   **Type / Scope**: a new screen modelled on `focus_manager_screen.dart`,
    without color.
*   **Proposed Changes**:
    *   a reorderable list;
    *   a menu on each row with Rename and Archive, with the archive
        confirmation from D7;
    *   an Add button;
    *   a name dialog with inline errors for `purpose_name_required` and
        `duplicate_purpose_name`.

    The screen sits behind the same `ProtocolsLockGate` as the list.

#### 36. `apps/mobile/lib/l10n/app_en.arb` (Modify) and generated l10n files (Regenerate)

*   **Type / Scope**: copy.
*   **Proposed Changes**: the PR 2 strings from D6 and D7, and the undo
    refusal for a duplicate Purpose name (file 14). A Purpose name is never
    combined with a verb in any string.

#### 37. `DESIGN.md` (Modify)

*   **Type / Scope**: design system prose. It adds no token.
*   **Proposed Changes**: under Components, add **Filter row:** chips that
    scroll sideways, single-select, with All first and a cyan edge on the
    selected chip only.

#### 38. `CONTEXT.md` (Modify)

*   **Type / Scope**: ubiquitous language.
*   **Proposed Changes**: add **Purpose** after Compound, and change
    Compound's sentence, both from [New and changed
    terms](#new-and-changed-terms).

#### 39. `docs/designs/protocol-schedules-and-reminders.md` (Modify)

*   **Type / Scope**: the living spec.
*   **Proposed Changes**: replace the neutral-instrument bullet "The app never
    categorizes a Compound by what it is or whether it is legal." with the
    three from [this spec's rule](#the-neutral-instrument-rule-narrowed), with
    a link here.

#### 40. `CHANGELOG.md` (Modify)

*   **Type / Scope**: release notes.
*   **Proposed Changes**: under `[Unreleased]`:
    *   **Added:** Purposes: tag Compounds, filter the Compound list and the
        picker by Purpose, and manage Purposes; Agent operations for Purposes,
        and `purposeIds` on Compounds.
    *   **Fixed:** a second device's seed no longer overrides a renamed
        built-in Compound.

#### 41. Tests for PR 2 (Modify, Create)

*   **`apps/mobile/test/features/protocols/protocols_repository_test.dart`:**
    *   **Seeding:** the starter Purposes are seeded once, even with an empty
        OTC source; a renamed or archived starter is left alone. A fresh seed
        inserts the six rows tagged, at the fixed timestamp.
    *   **Backfill:** an untouched upgraded row is tagged once, with an
        `otc_purpose_seed` entry; with `onlyNeverSynced`, its stamp is one
        second past the row's, and the batch can be undone; a renamed row, a row with an Agent or pulled
        entry, and a row with `[]` saved by the user are each left alone; a row
        the user emptied stays empty after Erase; a row whose only other entry
        was pulled with actor `otc_seed` is still untouched; a second run does
        nothing.
    *   **Compound writes:** creating stores `[]`; saving `[]` on a seed
        Compound stays `[]` after re-seeding and backfill; an unchanged edit
        including the list writes nothing; order is kept.
    *   **Purpose writes:** duplicate and empty names are rejected; undoing an
        archive into a duplicate name is reported as not applied.
*   **`apps/mobile/test/data/schema_snapshot_migration_test.dart`:** the
    65→66 upgrade adds the table and the column with `'[]'`, keeps every
    Compound, and clears the pull cursor.
*   **`apps/mobile/test/data/erase_all_data_test.dart`:** user Purposes are
    erased; the starter Purposes and seed Compounds keep their names and tags.
*   **`apps/mobile/test/data/portable_archive_repository_test.dart`:**
    *   the round trip keeps Purposes and `purpose_ids`;
    *   a version-65 archive imports;
    *   a newer row in a version-65 archive keeps the local tags.
*   **`apps/mobile/test/features/protocols/protocols_lock_sync_isolation_test.dart`:**
    Purposes follow the Protocols isolation the file already checks.
*   **`apps/mobile/test/features/activity/activity_feed_repository_test.dart`
    and `undo_conflict_message_test.dart`:** a Purpose change reads as `purpose`
    and can be undone; the duplicate-name refusal has its own message.
*   **`apps/mobile/test/features/protocols/protocols_day_controller_seed_test.dart`
    (Create):** a device with no account backfills; a signed-out device leaves
    rows it synced to the next signed-in Sync Run and still tags rows that never
    synced; a signed-in device doesn't backfill; a failed auth read skips it and
    the next open retries.
*   **`apps/mobile/test/features/sync/sync_cycle_runner_test.dart`:** the
    backfill runs after the drained pull and not when a push or a pull throws,
    and pending backfill rows are pushed in the same run.
*   **`apps/mobile/test/features/sync/sync_repository_test.dart`:** Purposes
    push before Compounds; a pull applies a Purpose; a Compound payload with no
    `purpose_ids` keeps the local list; a full pull of this device's own
    unchanged seed rows doesn't touch them, so the backfill still tags them (a
    last-writer-wins tie, with no Activity Log entry); a full pull restores the
    tags an older build dropped from a row it applied, with no entry and no
    push, and the next edit pushes them; an older version, the same stamp from
    another device, and the same version over a row holding a list restore
    nothing.
*   **`apps/server/test/protocols-sync.test.mjs`:**
    *   `purposes` round-trips;
    *   a Compound push without `purpose_ids` keeps the stored list, and an
        explicit `'[]'` clears it;
    *   CUJ 6: device A empties Creatine's list and renames Cognition and
        syncs; device B seeds, pulls in full, runs the backfill, and syncs;
        both end with an empty list and the new name;
    *   CUJ 6 on a device that backfilled with no account: its seed entry and
        its entry one second later lose to device A's edit, and are applied
        to a row nobody edited.
*   **`apps/server/test/seeded-row-tenancy-sync.test.mjs`:** two accounts can
    each hold starter Purpose ids.
*   **`apps/server/test/agent-protocols.test.mjs`:**
    *   list Purposes, with and without the starter merge and with
        `includeArchived`;
    *   the batch-write name rules;
    *   `purposeIds` on read;
    *   the `purpose` filter (CUJ 9);
    *   undoing a first tagging of a row with no key reads `[]`;
    *   `purposeIds` omitted keeps the list, and `[]` clears it;
    *   `purpose_not_found` for an unknown and an archived id;
    *   a Purpose write is undoable through the Activity Log.
*   **`apps/server/test/agent-mcp.test.mjs` and `agent-mcp-parity.test.mjs`:**
    the two tools are listed, and their results match REST.
*   **`packages/contract/test/agent-skill-reference.test.mjs`:** the two new
    commands are listed.
*   **`apps/mobile/test/features/protocols/compound_picker_sheet_test.dart`:**
    CUJ 4 at 200 Compounds with the filter: the selection kept across filter
    changes, search by Purpose name, and the Create row's pre-tagging.
*   **`apps/mobile/test/features/protocols/protocol_screen_test.dart`:** CUJ 1
    end to end, with the filter.
*   **`apps/mobile/test/features/protocols/compound_list_screen_test.dart`:**
    the filter and the search by Purpose name; CUJ 5; an archived tag kept on
    save.
*   **`apps/mobile/test/features/protocols/purpose_manager_screen_test.dart`
    (Create):** CUJ 8, covering rename, reorder, archive, add, and both name
    errors.
*   **`apps/mobile/test/features/protocols/compound_picker_real_database_test.dart`:**
    a Purpose added between opens is in the filter on the next open, and a
    Compound created under a filter is listed under it.
*   **`apps/mobile/test/l10n/l10n_externalization_test.dart`:** both new widget
    files are on its list, and no message takes a Purpose name as a placeholder.
*   **Accessibility:** the existing app-shell accessibility checks run on the
    filter rows and the Purpose manager in both themes, at 320 dp and 1.3×
    text.

## Verification Plan

Each item has an id. The PR sections of the Detailed Implementation Plan name
the items each one must pass.

*   **V1. Gate:** `pnpm ci:local --changed` passes for each PR.
    *   **PR 1 runs:** `mobile`.
    *   **PR 2 runs:** `mobile`, `golden`, `contract`, `js` and `sync`. The
        `js` and `sync` jobs need Docker.

    Don't run the emulator during the `mobile` job, because its timing
    budgets fail under load.
*   **V2. Golden vectors (PR 2):** `m40-compound-purposes` passes in Dart and
    in TypeScript. Changing one starter Purpose on one side fails the golden
    job.
*   **V3. Contract (PR 2):** `check:drift` is clean after regeneration. The
    diff shows exactly D9's additions.
*   **V4. Sync simulation (PR 2):** CUJ 6 is covered by
    `protocols-sync.test.mjs` (file 41). Upgrading one device at a time is
    covered by its server half there (a full pull returns the tags at the
    version an older build applied) and its app half in
    `sync_repository_test.dart` (that pull restores them, and the next edit
    pushes them). A device that upgrades with no account, backfills, and then
    signs in for the first time is covered in both too: against a server
    holding another device's newer removal and rename, it ends untagged and
    renamed and the server's row is unchanged, and an account with no edit
    receives the tags.
*   **V5. Tests:** the tests each PR adds pass inside its gate run: file 10 for
    PR 1, file 41 for PR 2. They include the repository tests against
    in-memory SQLite, the kill-and-reopen test and the accessibility checks.
*   **V6. Manual check on the emulator** (`perennia_pixel`, never a personal
    device): run CUJs 1, 3, 5 and 7 for PR 1, and CUJs 1, 5 and 8 for PR 2, on
    a debug build, and capture screenshots for each PR.

--------------------------------------------------------------------------------

<!-- Provenance: Indicates initial structural drafting via EGM. -->

*Drafted with EGM*
