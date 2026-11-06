# Platform Library Updates

*   **Author:** Leonardo Pinheiro
*   **Status:** Current
*   **Date:** 2026-11-05

Project conventions: [AGENTS.md](../../AGENTS.md),
[CONTEXT.md](../../CONTEXT.md), [ARCHITECTURE.md](../../ARCHITECTURE.md).

--------------------------------------------------------------------------------

## Overview

The Platform Library ships inside the app as a bundled seed file. This spec
defines what happens to an installed app when a new version brings a changed
library: new exercises appear, corrected exercises update, and exercises the
library no longer offers leave the app, unless the user has used them. A used
exercise stays, with its history, as the user's own exercise. Used means a live
Set, Workout entry or Template entry names the exercise. Live means the row's
`deleted_at` is null.

All of this runs on the device, on every launch, with no prompt and no network.
It writes only when the seed and the device differ, and it never writes a Set. A
kept exercise then syncs like any other User Library exercise, which needs one
change to the server's key for `exercises`.

## The Problem

An installed app takes only part of a library update:

| Library change | What an installed app does |
| :------------- | :------------------------- |
| New exercise | Adds it. |
| Rename or other correction | Updates Focuses, and fills equipment only where it was empty. Name, category, dimensions and notes stay as first installed. |
| Merged into another exercise | Archives it, even if the user logged it. The exercise leaves the library, and its Exercise Overview and analytics stop opening. |
| Removed outright | Nothing. It stays in the library. |

The library has already outgrown this. It has 1,546 exercises, and 309 ids it
once carried and no longer offers: 255 merged and 54 removed. Of those, 110 were
removed before the first seed committed to this repository. A further 84
exercises carry corrected names. Anyone with an app installed before those
changes keeps the old names and the removed exercises, and a user who logged a
merged exercise cannot open its history from the library. At the time of writing
the only installs are the project owner's hand-installed Android builds, but the
same gap would reach every future user.

More library changes are expected, such as new mobility and calisthenics
exercises, so each one needs to reach users without its own one-off migration.

## Goals

*   After the launch pass, every Platform row whose id the seed offers has the
    seed's name, category, equipment, Focuses and notes, and is active.
*   An exercise the library retires, by merge or removal, becomes the user's own
    exercise if it is used: same id, active, in the library, with its history
    and analytics intact.
*   A retired exercise that is not used disappears from the library, from search
    and from pickers.
*   A correction to an exercise the library still offers applies in place, even
    if the user has logged it, so history shows the corrected name. The user's
    own customized copies do not change. An Exercise Type is not corrected in
    place: changing one means retiring the id and adding a new one.
*   Devices that keep the same exercise converge on one row with no duplicate
    and no dialog. A user's edit to a kept exercise, made after the retirement
    stamp, wins over another device's automatic keep.
*   A Set or Template entry that arrives later for a hidden exercise, by sync or
    by import, is accepted, and the exercise is kept at the next launch.
*   Agents see what the app shows: a kept exercise is the user's own, and its
    Sets are not combined with the exercise it was merged into.
*   Shipping a new library takes a regenerated seed and no new migration code.

## Non-Goals

*   **Moving history onto the merge target.** Sets stay on the exercise they
    were logged against, so progress stays split between a kept exercise and the
    library exercise it merged into. Alternative D gives the reasons.
*   **A merge prompt.** Nothing asks the user to combine a kept exercise with
    the library's. Sync and update behavior stay silent.
*   **Keeping the old name after a rename.** An id cannot be both the user's and
    the library's. Keeping an old name for the user would require a new id for
    the library's version, and it would preserve typos indefinitely.
*   **Library updates outside app releases.** The library changes only when the
    app updates. There is no remote download.
*   **Adding exercises in this change.** The mechanism supports it; the content
    is separate work.
*   **Keeping an unused favorite.** A favorite holds no history, so it does not
    count as used. Risks and Mitigations states the cost.
*   **Other bundled catalogues.** Foods and OTC Compounds are out of scope.

## Open Questions

None.

## Critical User Journeys (CUJs)

### CUJ 1: A logged exercise is renamed

*   **Given**: The user has logged Sets against a library exercise, and the new
    version corrects its name.
*   **When**: The user opens the updated app.
*   **Then**: The library, the Exercise Overview and past Workouts all show the
    new name. The exercise stays in the Platform Library. No Set changes.

### CUJ 2: A logged exercise is merged

*   **Given**: The user has logged `Plank`, and the new version merges it into
    `Full Plank`.
*   **When**: The user opens the updated app.
*   **Then**: `Plank` is a User Library exercise with all its history.
    `Full Plank` is in the library as a separate exercise, without those Sets.

### CUJ 3: A logged exercise is removed

*   **Given**: The user has logged an exercise that the new version removes
    outright.
*   **When**: The user opens the updated app.
*   **Then**: The exercise is a User Library exercise with all its history, as
    in CUJ 2, and the library has no replacement for it.

### CUJ 4: An unused exercise is merged or removed

*   **Given**: No live Set, Workout entry or Template entry names the exercise,
    whether or not the user marked it a favorite.
*   **When**: The user opens the updated app.
*   **Then**: It is gone from the library, search, pickers and the Archived
    exercises screen.

### CUJ 5: A new exercise ships

*   **Given**: The new version adds an exercise to the library.
*   **When**: The user opens the updated app.
*   **Then**: It is in the library, in its category and Focuses.

### CUJ 6: A Set arrives later for a hidden exercise

*   **Given**: A hidden exercise on this device, and another device, or an older
    backup, holds a Set logged against it.
*   **When**: That Set arrives by sync or import.
*   **Then**: The Set is accepted. The exercise becomes a User Library exercise
    on this device at the next launch, or earlier if another device has already
    pushed the kept row.

### CUJ 7: A Template names a retired exercise

*   **Given**: A Template, archived or not, has a live entry for an exercise
    with no Sets, and the new version retires that exercise.
*   **When**: The user opens the updated app, then starts or edits the Template.
*   **Then**: The exercise is a User Library exercise. The Template is
    unchanged, starts as before and saves as before.

### CUJ 8: Two devices update at different times

*   **Given**: Two devices with the same logged exercise. Device A updates and
    the user renames the kept exercise there. Device B updates later.
*   **When**: Device B syncs.
*   **Then**: Both devices show the user's name. Device B's automatic change
    does not overwrite the user's edit, and no conflict is shown.

### CUJ 9: The user already has an exercise with that name

*   **Given**: The user customized a library exercise, so they have a User
    Library exercise with the same name, and they logged Sets against the
    library exercise before customizing it. The library then retires it.
*   **When**: The user opens the updated app.
*   **Then**: Both are active User Library exercises with one name and their own
    history. Saving an edit to either is refused with the existing
    duplicate-name error until one of them is given a different name.

### CUJ 10: An update during a Workout

*   **Given**: A Workout in progress includes an exercise the update retires,
    and the app is killed and reopened on the new version.
*   **When**: The user continues logging.
*   **Then**: The Workout entry makes the exercise used, so it is kept at that
    launch. Logging continues with no error and no lost Set.

### CUJ 11: An agent reads a kept exercise

*   **Given**: The user's kept `Plank` has synced to the server.
*   **When**: An agent reads that exercise or its progress.
*   **Then**: It sees a User Library exercise with its own Sets. `Full Plank`'s
    progress does not include them.

## Technical Plan (Architecture)

### The launch pass

Each launch runs one seeding pass, in one transaction, the first time something
needs the library (`ensurePlatformLibrarySeeded` in
`apps/mobile/lib/data/repositories/training_repositories.dart`). That pass is
currently a sequence of special cases: insert missing ids, archive redirects,
backfill empty equipment, reconcile Focuses, clean legacy notes. This spec
replaces those exercise steps with one comparison of the device against the
seed.

Each row is written at most once per pass, with one Activity Log entry:

| Case | Written values | Compared to decide a write |
| :--- | :------------- | :------------------------- |
| Id in `exercises`, no row | Seed fields; `loadMode` added, `recordProfile` from `defaultRecordProfileFor`, `defaultLoadUnit` kilogram, `isUnilateral` and `usesRpe` false; `libraryOrigin` platform | Not applicable |
| Id in `exercises`, Platform row | `name`, `categoryId`, `equipmentIds`, `focusIds`, `notes` from the seed; `deletedAt` null; `updatedAt` from the seed | Those fields and `deletedAt`, with lists compared as sets. `updatedAt` alone never triggers a write. |
| Id in `retired_exercises`, no row | Hidden, from the record, with the same defaults as the first case | Not applicable |
| Id in `retired_exercises`, Platform row, not used | Hidden: the record's `name`, `dimensionIds`, `categoryId`, `equipmentIds`, `focusIds`, `notes`; `recordProfile` recalculated if dimensions differ; `updatedAt` = `updated_at`; `deletedAt` = `retired_at` | All of those, including both stamps |
| Id in `retired_exercises`, Platform row, used | Kept: the same fields; `libraryOrigin` user; `updatedAt` = `retired_at`; `deletedAt` null. Older unacknowledged Activity Log entries for the id are acknowledged in the same transaction. | Not applicable: this state ends with the write |
| User Library row, any id | Never touched | Not applicable |
| Platform row in neither list | Never touched | Not applicable |

`isFavorite`, `loadMode`, `defaultLoadUnit`, `isUnilateral` and `usesRpe` are
never written on an existing row. Platform rows are read-only to users, so a
Platform row with `deletedAt` set can only come from an earlier pass or an
imported archive, and the pass corrects it.

Stamps compare in whole seconds, the precision a stored row keeps, and
`dimensionIds` compares in its encoded form, so a row the pass wrote matches
its record on the next launch. The Used query is skipped when no retired id
has a Platform row, which includes a fresh install.

Because the pass compares fields and not versions, it is idempotent: with
nothing to change it writes nothing, and a new library needs no new migration
code. It replaces `_applyPlatformExerciseRedirects`,
`_backfillExistingPlatformSeedEquipment`, `_sanitizeLegacyWgerAttributionNotes`
and `_reconcilePlatformSeedFocuses`, including that last function's one-time
Focus fill for customizations. The fill's trigger, a Platform row with empty
Focuses, no longer occurs: `focus_ids` is non-empty for every seed exercise, and
an install from before Focus has already run it.

A Platform row in neither list cannot come from a released seed: every id in all
5 committed seeds is in one of the two lists. The pass leaves such a row alone,
and hand-written test fixtures rely on that.

Each write appends an Activity Log entry, with the actor of whichever caller ran
the pass first (`app` from Today, `platform_seed` otherwise). Activity Log
entries are the sync push queue: a local write appends one, and push reads only
those entries. The existing `_guardAgainstPlatformExerciseRows` acknowledges
entries whose row is currently a Platform row, so Platform changes never reach
the server.

### Retired Exercise

New [CONTEXT.md](../../CONTEXT.md) term, added in the implementation pull
request:

> **Retired Exercise**: A Platform Library exercise the library no longer
> offers, because it was merged into another exercise or removed. Its id is
> never reused. If a live Set, Workout entry or Template entry names it, it is
> **kept**: it becomes a User Library exercise with the same id. Otherwise it is
> **hidden**: a Platform row with `deletedAt` set, shown nowhere. Hidden is not
> Archived, which is a state the user chooses and can reverse.

The [CONTEXT.md](../../CONTEXT.md) entry for User Library gains "or kept from
the Platform Library".

**Used** is defined by one query, run once per launch and restricted to the
retired ids whose rows are Platform rows, so it does not read all history:

```sql
SELECT exercise_id FROM logged_sets
  WHERE deleted_at IS NULL AND exercise_id IN (...)
UNION
SELECT exercise_id FROM workout_exercises
  WHERE deleted_at IS NULL AND exercise_id IN (...)
UNION
SELECT exercise_id FROM template_exercises
  WHERE deleted_at IS NULL AND exercise_id IN (...)
```

Each branch checks only its own row. So a Planned Set counts, because a Workout
naming the exercise must keep working, and a live entry in an archived Template
counts, because that Template can be restored. Deleting a Workout soft-deletes
its children, so a deleted Workout does not count. A deleted Set does not count
either: if it is restored later it is live at the next launch, and the exercise
is kept then. A favorite does not count.

### Hide, do not delete

A hidden exercise is shown nowhere: the library, search and pickers read active
rows, and the Archived exercises screen reads only User Library rows
(`listArchivedUser`).

The row stays because `logged_sets`, `workout_exercises` and
`template_exercises` all have foreign keys to `exercises`, and the app runs with
`foreign_keys = ON`. A Set can still arrive for that id from another device or
an old backup, and without the row the write would fail. For the same reason the
pass inserts a hidden row for every retired id on a fresh install. The old
redirect step does that only for merged ids and gives them the target's name;
removed ids get no row at all, so a pulled Set against one would fail its
foreign key.

The sync cycle does not currently wait for seeding.
`RepositorySyncCycleRunner.run`
(`apps/mobile/lib/features/sync/services/sync_cycle_runner.dart`) will await
`ensurePlatformLibrarySeeded` first, inside its existing error handling so a
failure reaches Sync Status. The runner takes this as a constructor callback
that defaults to nothing, set only in `sync_providers.dart`, so tests of pull
alone do not change.

### Keep in place

Keeping an exercise updates its row and leaves its id alone, so no Set, Workout
or Template is rewritten. The next sync pushes it, because the guard checks the
row's current origin. Entries the row queued while it was a Platform row are
acknowledged in the keep transaction, so only the kept image goes out.

Keep runs only in the launch pass. There is no other keep path:

*   **After a pull.** A Set or Template entry that arrives for a hidden exercise
    is accepted, and the exercise stays hidden until the next launch, unless the
    same pull brings the kept row another device pushed.
*   **After an import.** `importPortableArchive` does not change. It merges
    archive rows as it always has, including Platform rows, which can write an
    old name or reactivate a removed exercise. The next launch corrects those
    rows by the table above. The app seeds on Today before import can be
    reached, so import needs no seeding await of its own.

Risks and Mitigations states what the user sees until that next launch.

A kept exercise's name can match another exercise. Keep has no special case for
this. If it matches an active Platform exercise, it becomes a Shadowing exercise
under the existing rule. If it matches an active User Library exercise, both
stay active (CUJ 9). Pull can already produce that state, because
`_ensureUniqueActiveUserName` runs only on local writes.

### Timestamps make devices agree

Each retired record has a fixed `retired_at`, later than its own `updated_at`,
and a retired record is frozen once written. A hidden row has
`updatedAt = updated_at` and `deletedAt = retired_at`. A kept row has
`updatedAt = retired_at`. Every device computes the same stamp, and these
outcomes follow from the existing last-write-wins rule:

| Situation | Result |
| :-------- | :----- |
| Two devices keep the same exercise | Same stamp, so the device-id tie-break picks one. Only `isFavorite` can differ, so a device-local favorite can be lost. |
| Device A keeps it, the user renames it there, device B updates later | The rename's stamp is later than `retired_at`, so B's automatic push loses and B pulls the rename (CUJ 8). |
| Device holds it hidden and pulls the kept row | `retired_at` is later than the hidden row's `updatedAt`, so the kept row applies. |

A stamp taken from the clock at keep time would break the second row, because
B's automatic change would overwrite the user's rename. The push that loses goes
to the Activity Log as usual, with no dialog.

The hidden row's stamp must hold even if a favorite wrote a later one: a
Platform row's `setFavorite` stamps the current time. That is why the "not used"
case compares the stamps, and why the sync cycle runs the pass before it pulls.

### Seed format

The seed gains `retired_exercises`, sorted by id:

```json
{ "id": "...", "name": "...", "dimension_ids": [], "category_id": "...",
  "equipment_ids": [], "focus_ids": [], "notes": null,
  "updated_at": "...", "retired_at": "...", "source_attribution": {} }
```

`source_attribution` is omitted where the source record has none. All 309 ids
are listed, including the 110 from before the first committed seed, because the
old redirect step creates a row for each merged id on any install, so a device
can hold them.

`buildRetiredExercises` in `tools/platform-exercise-cleanup.mjs` builds the
list:

*   It keeps the list append-only: a record in the previous seed's
    `retired_exercises` is carried forward unchanged, including its stamp and
    `focus_ids`.
*   A newly retired id takes its fields from the previous seed's `exercises`
    record when there is one, so a corrected name survives, and from the source
    record otherwise, with `focus_ids` from the same rule as live exercises. Its
    `retired_at` is the new manifest field `retiredAt` in
    `tools/data/platform-exercise-review-decisions.json`.
*   It fails if an id in the previous seed is in neither new list, an id is in
    both, a live id's `dimension_ids` differ from the previous seed, a retired
    `category_id` is not in the seed's categories, a `retired_at` is not later
    than its `updated_at`, or `retiredAt` is missing or invalid. When a run
    retires something new, `retiredAt` must also be later than the manifest's
    top-level `reviewedAt`.

No live id has changed `dimension_ids` across all 5 committed seeds.

The data license notice is built from both lists, because retired names ship in
the bundle. The seed grew from about 1.9 MB by about 390 KB.

`exercise_redirects` lists each merged id and its target, with no entry for a
removed id. It stays for the server. The app stops reading it, because retiring
needs no target.

### Server key

The server's `exercises` table moves from `id` to (`user_id`, `id`). Retired ids
are fixed and shared by every install, so with `id` alone the first account to
keep `Plank` would own the row. Every other account's push would be dropped by
the owner check in `pushOpaqueSyncRowsInTransaction`, its rename would never
sync, its agent reads would still fold, and its stuck entries would hold up
later Exercise pushes.

This repeats what `0032_chemical_may_parker.sql` did for other tables with fixed
ids. Rows keep their values, because existing ids are unique, and no table has a
foreign key to `exercises`. `pushExercisesInTransaction` becomes a wrapper over
`pushAccountKeyedSyncRowsInTransaction`. Only `sync.ts`'s push read and update
use the id alone; every other reader is already scoped by user.

### Agent surface

No new operation, no MCP tool change, and no contract diff. Behavior changes in
one place: the server treats seed redirects as global, so a kept exercise would
still read as its merge target, and its Sets would be folded into that target.

An exact match on the user's own exercises now wins over a redirect:

*   `createInMemoryAgentCatalogStore` in `apps/server/src/agent-catalog.ts`
    checks for an exact id among the caller's exercises before applying the
    redirect, in `getExerciseById` and `getExercisesByIds`. The Drizzle store's
    `getExerciseById` stops resolving the id first, so the id reaches this check
    unchanged. Visibility and `includeShadowed` then work as for any User
    Library exercise, which includes archived rows.
*   `loadExerciseIdResolver(db, userId)` loads the user's rows whose ids are
    redirect sources and returns `resolve(id)` and `idsResolvingTo(id)`. Every
    call in `apps/server/src/agent-progress-reads.ts` uses it. An archived row
    counts as kept.
*   `apps/server/src/agent-read-surface.ts`, where a Set is joined to its
    exercise, looks up the raw id, then the redirect, with no new query.

A user with no kept row reads as before, including Sets from a device that has
not updated. Platform catalog rows are built from the seed's `exercises`, so a
retired id can only match a user's own row.

### Invariants

| Invariant | How this treats it |
| :-------- | :----------------- |
| A Workout is a session | Not touched. |
| Sets are self-describing | No Set is written. An Exercise Type is not corrected in place; a changed one needs a new id. |
| Derived analytics are never stored | Nothing derived is stored. A kept exercise's records are computed from its Sets as before. |
| User-facing delete = archive, no cascades | Hiding is an exception, and not a user-facing delete: no user action triggers it, only unused Platform rows qualify, the row is soft-deleted, and nothing cascades. A used exercise stays. |
| Restore/import is merge-only | Import code does not change. |
| Local writes never block | The pass runs at launch, as it does now. The Set save path is unchanged. |
| Sync is silent LWW | Retirement stamps are fixed, no dialog is added, and losers reach the Activity Log. |
| Validation is one shared module | No rule changes. No golden vector changes. |
| No behavioral analytics | None added. |

There is no Drift schema change, no client migration, and no change to the sync
shape. There is one Postgres migration.

### Validation and analytics

No validation rule changes, in either tier. No analytics computation changes,
and no golden vectors change. Progress reads for a kept exercise now return that
exercise's own Sets, which the server tests in the Verification Plan cover.

## Risks and Mitigations

*   **Progress stays split after a merge.** Accepted: see Alternative D. A merge
    the user starts is listed under Future Improvements.
*   **An exercise added to a Workout by accident is kept,** unless it was
    removed before the update. Accepted: the user can archive it, and the
    alternative is a Workout that shows "Unknown exercise".
*   **Two exercises can share a name** (CUJ 9). Editing either raises
    `DuplicateExerciseNameException` until one is renamed. Accepted: pull can
    already reach this state, and archiving one automatically would hide a
    logged exercise, which is the defect this spec removes.
*   **A hidden exercise can be referenced until the next launch,** after a pull
    or an import. Until then Today shows "Unknown exercise", the Navigation
    Panel omits the row, its Exercise Overview does not open, and saving a
    Template that names it is refused. An imported Platform row can also show in
    the library under an old name. The next launch corrects all of these, and no
    data is lost in between. If another device already pushed the kept row, it
    arrives in the same pull.
*   **A rename can end a Shadowing link.** A customization named after the old
    name no longer shadows the renamed exercise, so both appear. The user can
    archive their copy. A rename can also start a link, under the same existing
    rule.
*   **An unused favorite is lost** when it is retired. It holds no history, and
    counting favorites would keep exercises the library meant to remove, with no
    logged data to protect.
*   **A device-local favorite can be lost on a kept exercise** when two devices
    keep the same exercise, because the tie-break picks one row.
*   **An undo of a seed-written Activity Log entry lasts until the next
    launch,** because the pass reapplies the seed. A User Library row is never
    reapplied.
*   **A seed defect fails every launch and every sync cycle,** because the pass
    is one transaction and the sync cycle awaits it. The generator rejects an
    unknown retired `category_id`, the asset test parses the bundled file, and a
    failed pass clears its memoized future, so each caller retries and the
    failure reaches Sync Status.
*   **A mistaken retirement cannot be undone.** A user's kept row cannot be
    reclaimed, and the generator rejects a retired id that reappears. Recovery
    is to ship the exercise under a new id.
*   **The retired list only grows.** Each record adds about 1.3 KB to the
    bundle and one hidden row per install. Retirements are rare, so this is
    acceptable for now.

## Alternatives Considered

### Alternative A: Copy a used exercise to a new User Library id

Create a new row, as customizing does, and point the user's Sets at it.

*   **Pros**: The retired id stays a pure Platform row, so the server's global
    redirect could stay as it is, and the server re-key would not be needed.
*   **Cons**: Every logged Set and Template entry has to be rewritten, which
    breaks the rule that history is not touched and creates a large synced
    write. Each device would generate its own new id, so two devices would
    produce duplicate exercises for one history, unless the id were derived from
    the old one.
*   **Reason for Rejection**: Keeping the same id needs no rewrite, and devices
    agree without coordinating. The re-key is two statements and follows a
    precedent.

### Alternative B: Hard-delete an unused retired exercise

Remove the row, which is the literal reading of "deleted from the app".

*   **Pros**: No hidden rows. A slightly smaller database.
*   **Cons**: `logged_sets`, `workout_exercises` and `template_exercises` have
    foreign keys to `exercises`, and `foreign_keys` is on. A Set pulled from
    another device or imported from an old backup would fail. Avoiding that
    would need a new "recreate the row on arrival" path, which needs the same
    retired records anyway.
*   **Reason for Rejection**: The user cannot tell the two apart, and a soft
    delete keeps every foreign key satisfied. Fresh installs already keep rows
    this way for merged ids.

### Alternative C: Keep the user's version when a used exercise is corrected

Treat a rename like a retirement: the user keeps the old name, and the library's
corrected version gets a new id.

*   **Pros**: Nothing the user logged ever changes appearance.
*   **Cons**: A user who logged `Shrimp Squad` keeps the typo as their own
    exercise, next to the corrected one, with progress split across both. The
    library would also need new ids for every correction.
*   **Reason for Rejection**: A correction is the same exercise, so its history
    should follow it.

### Alternative D: Move history onto the merge target

When an exercise merges, repoint its Sets at the target, so progress stays in
one place.

*   **Pros**: One exercise and one progress line, which is what a merge means.
*   **Cons**: It rewrites logged history across every device, and the rewrite
    cannot be fully undone once later Sets are mixed in. A merge judged right
    for the library, such as two machine variants, may be wrong for the person
    who logged one of them. Records and bests would change with no action from
    the user.
*   **Reason for Rejection**: It conflicts with self-describing Sets, and the
    cost of split progress is smaller than the cost of a wrong merge that cannot
    be undone. A user-driven merge remains possible later.

### Alternative E: Rewrite Template entries instead of keeping the exercise

For a retired exercise that appears only in a Template, point the entry at the
merge target and leave the exercise hidden.

*   **Pros**: Fewer kept exercises, and Templates use the current library.
*   **Cons**: It is a synced write to the user's plan with no action from them.
    It can collide with `template_exercises_active_exercise_unique` when the
    Template already has the target. A removed exercise has no target at all, so
    it would need a second rule. Prescriptions may also not fit the target's
    dimensions.
*   **Reason for Rejection**: Counting the entry as used needs one branch in one
    query and no write to the plan.

### Alternative F: A versioned migration for each library release

Store a library version and run a hand-written step for each change, or use a
Drift schema migration.

*   **Pros**: Explicit about what changed in each release, and the pass could be
    skipped when the version matches.
*   **Cons**: Each library update needs new code, which is the cost this spec
    removes. A missed or wrong step leaves devices permanently different, and
    nothing corrects them later. Library data is not a schema change.
*   **Reason for Rejection**: Comparing against the seed corrects earlier drift
    in the fields it compares, including rows written by past special cases.

### Alternative G: Skip the pass with a seed hash

Store a hash of the seed and do nothing at launch when it matches.

*   **Pros**: Saves the comparison on most launches.
*   **Cons**: Adds stored state and a way to be stuck: a device with the current
    hash and a wrong row is never corrected. The current pass already reads
    every exercise row more than once per launch, so one comparison is not an
    added cost.
*   **Reason for Rejection**: Nothing has measured a problem it would solve. It
    can be added later if the cold start budget is missed.

### Alternative H: Download library updates from the server

Fetch library changes without an app update.

*   **Pros**: Corrections reach users sooner.
*   **Cons**: The app must work offline with no account, so a bundled copy is
    needed anyway. It would add a second delivery path, and app and server could
    disagree about the library.
*   **Reason for Rejection**: The library changes rarely enough that arriving
    with an app update is sufficient.

### Alternative I: Leave a used retired exercise as an active Platform row

A used retired exercise stays an active Platform row that never syncs, and only
an unused one is hidden.

*   **Pros**: Removes the server re-key, `retired_at` and the timestamp rules,
    and devices cannot disagree about a row that does not sync.
*   **Cons**: Agents would still fold merged Sets into the target, a removed id
    would have no name on the server, and a rename by the user would fork a new
    id through customizing, splitting progress.
*   **Reason for Rejection**: It does not deliver "the exercise is the user's
    own", and agents would keep seeing something different from the app.

--------------------------------------------------------------------------------

## Non-Functional Requirements

*   **Performance.** The launch pass runs before the library is first read, on
    every launch, and the existing `coldStartHomeInteractiveBudget` of 2 seconds
    must still pass. The Used query runs once per pass. `logged_sets` and
    `template_exercises` have an `exercise_id` index; `workout_exercises` does
    not, so that branch scans that table once per launch. The Set save path is
    not touched, so `setSaveConfirmationFrameBudget` is unaffected.
*   **First launch after an update.** The first pass writes every changed row
    and its Activity Log entry in one transaction: about 400 rows for an install
    from before these library changes. A fresh install writes more than that.
*   **Crash safety.** The pass is one transaction, so a kill leaves the old
    state, and the next launch runs it again.
*   **Security and privacy.** No new data leaves the device. A kept exercise
    syncs like any User Library exercise, only for a signed-in user, and the
    re-key keeps it in that user's own row. No personal data enters the seed.
*   **Rollout and rollback.** There is no flag. The server ships first through
    `db:migrate`, and the re-key changes nothing for an account with no kept
    rows. At the time of writing, the only installs are the project owner's
    hand-installed Android builds. Tagged hand-install builds exist, and an
    older build that pulls a kept exercise fails its seed step, because
    `_applyPlatformExerciseRedirects` throws on a User Library row. Release
    notes tell multi-device users to update together, and rolling the app back
    is safe only to a build containing this spec. A Self-Hosted Deployment that
    lags the app keeps folding a kept exercise's Sets into its target until it
    updates.

--------------------------------------------------------------------------------

## Additional Resources

*   [CONTEXT.md](../../CONTEXT.md): Platform Library, User Library, Shadowing,
    Active / Archived.
*   [ARCHITECTURE.md](../../ARCHITECTURE.md): the app's layering and the sync
    model.
*   [AGENTS.md](../../AGENTS.md): the non-negotiable invariants and the gate.

## Future Improvements

*   **A merge the user starts.** Combine a kept exercise with its merge target
    on request, which would need its own spec. `exercise_redirects` already
    records the target.

--------------------------------------------------------------------------------

## Detailed Implementation Plan

Two pull requests, each targeting `main`, not stacked. PR 2 reads the seed data
from PR 1, so it opens after PR 1 has merged. The app ignores the new seed key
until then, and no kept rows exist yet.

### PR 1: Server key, agent reads and seed data

**Verification Plan items:** the Gate (`pnpm ci:local mobile js contract sync`),
Data, and Server and generator tests.

#### `tools/data/platform-exercise-review-decisions.json` (Modify)

*   **Type / Scope**: Reviewed manifest.
*   **Proposed Changes**: Add top-level `retiredAt: "2026-11-05T00:00:00.000Z"`,
    the stamp for any exercise retired for the first time in a generator run. A
    later library change that retires exercises sets a later value.

#### `tools/platform-exercise-cleanup.mjs` (Modify)

*   **Type / Scope**: Generator module.
*   **Proposed Changes**:
    *   `applyPlatformExerciseCleanup` also returns `excludedIds`.
    *   Export pure
        `buildRetiredExercises({ previousSeed, sourceRecords, cleanup, retiredAt, reviewedAt, categories, focusIdsFor })`,
        returning the sorted `retired_exercises` list. `sourceRecords` is the
        input given to `applyPlatformExerciseCleanup`. `previousSeed` is null on
        a first run, and a seed with no `retired_exercises` counts as an empty
        list. It follows the rules and failures in the Seed format section, with
        a named error for each failure.

#### `tools/platform-exercise-focus.mjs` (Modify)

*   **Type / Scope**: Generator module.
*   **Proposed Changes**: Export `focusIdsForRetired(record, categoryName)`,
    which returns Focus ids from `focusKeysFor` in starter-Focus order, with no
    override or starter lookup. `withSeedFocuses` does not change: it passes
    `retired_exercises` through untouched, which is what keeps those records
    frozen and `--check` stable.

#### `tools/generate-wger-platform-exercises.mjs` (Modify)

*   **Type / Scope**: Generator.
*   **Proposed Changes**: Read the current output file first, if it exists, as
    `previousSeed`. Call `buildRetiredExercises`, and write `retired_exercises`
    after `exercises`. `buildDataLicenseNotice` reads the attributions of both
    lists. `exercise_redirects` is unchanged.

#### `apps/mobile/assets/seeds/platform_exercises.json` and `apps/mobile/assets/seeds/platform_exercises.LICENSE.md` (Modify)

*   **Type / Scope**: Generated data.
*   **Proposed Changes**:
    1.  Check out wger at `ea78447`.
    2.  Fetch `https://workout.cool/api/exercises/all?page=N&limit=100` for
        every page up to `pagination.totalPages`, and write the records from all
        pages as one JSON array to a file outside the repository.
    3.  Run
        `WGER_REPO=<path> WORKOUT_COOL_EXERCISES_PATH=<file> node tools/generate-wger-platform-exercises.mjs`,
        then `node tools/generate-server-platform-exercise-seed.mjs`.
    4.  Check: `retired_exercises` has 309 records, and `exercises` and
        `exercise_redirects` are unchanged except by key order.

    Stop condition: Workout.cool is not pinned, so step 4 can fail. If
    `exercises` or `exercise_redirects` differ, do not commit them. Add
    `retired_exercises` to the committed seed from the generated file's list,
    regenerate the license notice from that seed, and record this in the pull
    request. If the generator itself fails because Workout.cool no longer has an
    id the manifest names, stop and report it.
    `apps/server/src/data/platform-exercise-seed.generated.ts` reads only the
    existing keys, so its drift check must pass with no change.

#### `apps/server/src/db/schema.ts` and a new migration in `apps/server/drizzle/` (Modify, Create)

*   **Type / Scope**: Postgres schema.
*   **Proposed Changes**: Remove `.primaryKey()` from `exercises.id` and add a
    composite `primaryKey` on `userId` and `id`, as `mealTypes` has. Generate
    the migration with `pnpm db:generate`, taking the next free number (0036,
    because `0035_purposes` landed first). It drops `exercises_pkey` and adds
    the composite key.
    Add a header comment as `0032_chemical_may_parker.sql` has.

#### `apps/server/src/sync.ts` (Modify)

*   **Type / Scope**: Server, sync push.
*   **Proposed Changes**: Add `typeof schema.exercises` to
    `AccountKeyedSyncTable`. `pushExercisesInTransaction` becomes a wrapper over
    `pushAccountKeyedSyncRowsInTransaction` with `table: schema.exercises` and
    `entityTable: EXERCISES_SYNC_ENTITY`, as
    `pushExerciseCategoriesInTransaction` is.

#### `apps/server/src/agent-catalog.ts` (Modify)

*   **Type / Scope**: Server, catalog.
*   **Proposed Changes**:
    *   In `createInMemoryAgentCatalogStore`'s `getExerciseById` and
        `getExercisesByIds`: if `callerCatalogExercises` holds the exact id, use
        it; otherwise apply `resolvePlatformExerciseId`.
    *   Remove the pre-resolve in the Drizzle store's `getExerciseById`.
    *   Add `loadExerciseIdResolver(db, userId): Promise<ExerciseIdResolver>`,
        where `ExerciseIdResolver` has `resolve(id): string` and
        `idsResolvingTo(id): string[]`. It reads the ids of the user's
        `exercises` rows, archived included, that are seed redirect sources. A
        kept id resolves to itself and is left out of its former target's list.
    *   `resolvePlatformExerciseId` and `exerciseIdsResolvingTo` keep their
        signatures and stay exported.

#### `apps/server/src/agent-progress-reads.ts` and `apps/server/src/agent-read-surface.ts` (Modify)

*   **Type / Scope**: Server, reads.
*   **Proposed Changes**: In `agent-progress-reads.ts`, load one resolver per
    read, and use it at every current use of the global functions:
    `readExerciseProgressSets`, `loadPerformedWorkoutSets` (the SQL filter and
    the grouping), and the distinct-exercise read. Update the doc comment on
    `loadPerformedWorkoutSets` to state the rule. In `agent-read-surface.ts`,
    where a Set is joined to its exercise, look up
    `exercisesById.get(set.exerciseId)` first, then the redirect.

#### `docs/development.md` (Modify)

*   **Type / Scope**: Developer docs.
*   **Proposed Changes**: Add "Updating the Platform Library" after "Refreshing
    the Open Food Facts bundle": edit the manifest, raise `retiredAt` when
    retiring, run the commands above, keep an Exercise Type fixed for a live id,
    and never reuse a retired id.

#### Tests (Modify)

*   `apps/server/test/platform-exercise-cleanup.test.mjs`: one test per
    `buildRetiredExercises` rule: carry-forward leaves a record unchanged; a
    newly retired id prefers the previous seed's record; `source_attribution` is
    omitted where absent; and it fails for an id in neither list, an id in both,
    an invalid `retiredAt`, a `retiredAt` not later than `reviewedAt` when
    something new retires, changed dimensions, and an unknown category. A
    rename-only run accepts a `retiredAt` older than `reviewedAt`. Against the
    committed seed: `retired_exercises` covers every redirect source and
    excluded id, has no overlap with `exercises`, and every `retired_at` is
    later than its `updated_at`.
*   `apps/server/test/seeded-row-tenancy-sync.test.mjs`: add to `SEEDED_ROWS` an
    `exercises` entry with a retired id, `seededName: "Plank"`, and the fields
    `exercisePayload` in `exercises-lifecycle-sync.test.mjs` sends as `extra`.
*   `apps/server/test/exercises-lifecycle-sync.test.mjs` (75-102): user B's push
    now stores a second row, and user A's row keeps its payload. The test
    asserts two rows, one per account.
*   `apps/server/test/agent-exercise-catalog-batch-write.test.mjs` (487-515):
    the same change for a second account's batch write.
*   `apps/server/test/agent-catalog-db.test.mjs`: a kept id returns the user's
    row for that user, and still resolves to the target for another user. An
    archived kept row returns itself. A customization request naming a kept id
    is rejected as not a Platform exercise.
*   `apps/server/test/agent-progress-reads.test.mjs`,
    `apps/server/test/agent-read-surface.test.mjs`: a kept exercise reads only
    its own Sets, and its merge target does not include them. A user with no
    kept row folds as before.
*   `apps/server/test/sync-convergence.test.mjs`: two devices push the same kept
    row at the same stamp, one then renames it, and all devices converge on the
    rename.

### PR 2: App library updates

**Verification Plan items:** the Gate
(`pnpm ci:local mobile sync release_version`), Repositories against in-memory
SQLite, Sync simulation, Kill-and-reopen mid-workout, Performance,
Accessibility, and the Manual check.

#### `apps/mobile/lib/data/seeds/platform_exercise_seed.dart` (Modify)

*   **Type / Scope**: Seed loader.
*   **Proposed Changes**: Add `SeedRetiredExercise` (the Seed format fields
    except attribution) and `PlatformExerciseSeed.retired`. Remove
    `SeedExerciseRedirect` and `redirects`, which nothing in the app reads any
    more.

#### `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

*   **Type / Scope**: Repository.
*   **Proposed Changes**:
    *   In `_ensurePlatformLibrarySeeded`, keep category seeding and
        `_seedStarterFocuses`, and replace the exercise insert loop and the
        steps named in the Technical Plan with
        `_reconcilePlatformExercises(seed, context)`, which runs before
        `_seedStarterFocuses`. The early return also requires `seed.retired` to
        be empty.
    *   `_reconcilePlatformExercises` reads all exercise rows once, runs the
        Used query for retired ids with Platform rows, and applies the table in
        The launch pass section to `seed.exercises`, then `seed.retired`, each
        in id order. Keep sets `syncAcknowledgedAt` on the id's unacknowledged
        Activity Log entries before appending its own. A recalculated
        `recordProfile` uses `defaultRecordProfileFor` with the row's
        `loadMode`.
    *   Remove `_applyPlatformExerciseRedirects`,
        `_backfillExistingPlatformSeedEquipment`,
        `_sanitizeLegacyWgerAttributionNotes`, `_reconcilePlatformSeedFocuses`,
        and what only they use: `_equipmentListEquals`,
        `_legacyEquipmentMigrationFromNote`, `_cleanLegacyWgerAttributionNote`,
        `_legacyWgerAttributionPrefix`.
    *   `ExerciseRepository.create`, `customize` and the other user write paths
        do not change.
    *   Update the `eraseAllData` doc comment: Platform rows stay because hidden
        ones must keep resolving and the pass would reinstate them, not because
        seeding skips existing ids.

#### `apps/mobile/lib/features/sync/services/sync_cycle_runner.dart` and `apps/mobile/lib/features/sync/services/sync_providers.dart` (Modify)

*   **Type / Scope**: Sync.
*   **Proposed Changes**: `RepositorySyncCycleRunner` takes
    `Future<void> Function()? ensureLibrarySeeded`. `run` awaits it as the first
    statement inside its `try`, so a failure takes the existing failure path and
    reaches Sync Status. `syncCycleRunnerProvider` passes
    `() => ref.read(trainingRepositoriesProvider).catalog.ensurePlatformLibrarySeeded()`.

#### `apps/mobile/lib/features/sync/repositories/sync_repository.dart` (Modify)

*   **Type / Scope**: Sync.
*   **Proposed Changes**: Update the comment above
    `_guardAgainstPlatformExerciseRows` to say a kept row passes because its
    current origin is `user`. No behavior change.

#### `CONTEXT.md` (Modify)

*   **Type / Scope**: Vocabulary.
*   **Proposed Changes**: Add **Retired Exercise** after Shadowing, with the
    definition in the Technical Plan. Add "or kept from the Platform Library" to
    User Library's definition.

#### `CHANGELOG.md` (Modify)

*   **Type / Scope**: Changelog, under `## [Unreleased]`, `Changed`.
*   **Proposed Changes**: Add: "**Exercise library updates now reach installed
    apps.** Renames and corrections apply in place. An exercise the library
    merges or removes stays as your own if you logged it or have it in a Workout
    or Template, and disappears otherwise. Agents see a kept exercise as yours,
    with its own Sets. If you sync more than one device, update them together: a
    device on an older build can't update its exercise library once it pulls an
    exercise you kept." Reword the existing lines so they stay true: remove "On
    new installs," from the 80-names entry and "on new installs" from the
    non-English entry, and replace "On a device that already has a removed
    exercise it is archived, so sets logged under it keep their history." with
    "A removed exercise you used stays as your own, with its history." PR 1 is
    internal and adds no line.

#### `docs/designs/platform-library-updates.md` and `docs/designs/SITEMAP.md` (Modify)

*   **Type / Scope**: Spec status.
*   **Proposed Changes**: Set this spec's Status and its SITEMAP row to Current.

#### `apps/mobile/test/data/platform_library_update_test.dart` (Create)

*   **Type / Scope**: Repository tests against in-memory SQLite, with a fake
    `PlatformExerciseSeedSource`.
*   **Proposed Changes**: One test per rule, each on a new
    `TrainingRepositories` instance so the pass runs again:
    *   A new id inserts, with the stated defaults.
    *   A rename, category or notes change applies in place with Sets unchanged,
        and `isFavorite` is preserved. The new name shows through
        `ExerciseRepository.getById` and on a past Workout through
        `HomeRepository.watchWorkout` (CUJ 1).
    *   A Platform row whose only difference is `updatedAt` is not written.
    *   An id in `exercises` whose Platform row has `deletedAt` set is
        reactivated.
    *   Retired with a live Set is kept: same id, user origin, active, fields
        from the record, `updatedAt` equal to `retired_at`. Retired with a live
        Planned Set, a live Workout entry, a live Template entry, or a live
        entry in an archived Template is also kept, and the Template editor then
        saves.
    *   Retired with only a deleted Set, or a Set in a deleted Workout, is
        hidden. Restoring the Set and running the pass again keeps it.
    *   Retired and unused, including a favorite, is hidden with `updatedAt` =
        `updated_at` and `deletedAt` = `retired_at`, and is absent from
        `listActive`, `listArchivedUser` and search. A favorite stamped later
        than `retired_at` is rewritten to those stamps.
    *   A fresh install inserts a hidden row with the record's own name for
        every retired id.
    *   A second run writes nothing and appends no Activity Log entry.
    *   A kept row's older unacknowledged Activity Log entries are acknowledged,
        and the kept entry is not.
    *   Name match: a kept exercise named like an active User Library exercise
        stays active, and an edit to either throws
        `DuplicateExerciseNameException` until one is renamed.
    *   A row left by the old redirect step, with the target's name and stamp,
        is rewritten from the record, kept if used.
    *   A User Library row with a retired id or a seed id is never modified. A
        Platform row in neither list is never modified.
    *   Importing an archive with a merged alias and a removed active row, then
        running the pass on a new instance, gives each row the record's name and
        stamp.
    *   Set arriving after the pass: a Set inserted on a hidden id is accepted,
        and the next pass keeps the exercise (CUJ 6).

#### `apps/mobile/test/data/platform_library_update_reopen_test.dart` (Create)

*   **Type / Scope**: Kill-and-reopen, using
    `apps/mobile/test/support/kill_point_snapshot_interceptor.dart`.
*   **Proposed Changes**: Kill during the first pass, reopen, and check the pass
    completes with no partial state. Reopen mid-Workout on a new seed retiring
    an exercise in that Workout: the exercise is kept at that launch, Sets log
    with no error and none is lost (CUJ 10).

#### Existing tests (Modify)

*   `apps/mobile/test/data/exercise_catalog_repository_test.dart`: replace the
    two redirect tests and the legacy-note test with their equivalents under the
    new table, and remove `redirects` from fake seeds. The asset test also
    checks `retired_exercises`: 309 records, each with a known category.
*   `apps/mobile/test/features/sync/sync_cycle_runner_test.dart`: one new case:
    the callback is awaited before the first push, and a failing callback
    records a sync failure.
*   `apps/mobile/test/features/sync/sync_repository_test.dart`: a pulled Set and
    a pulled Template entry on a hidden id both apply. A pulled kept row applies
    over a hidden one. A device's automatic keep loses to a later pulled rename.
    Two devices' kept rows at one stamp converge by the device-id tie-break. The
    kept row pushes; a hidden row does not.
*   `apps/mobile/test/data/erase_all_data_test.dart`: hidden rows stay Platform
    rows. A kept row is erased like any User Library row, and a later pass
    leaves it alone.

## Verification Plan

*   **Gate**: `pnpm ci:local mobile js contract sync` for PR 1, and
    `pnpm ci:local mobile sync release_version` for PR 2. The `contract` job in
    PR 1 must show no diff.
*   **Data**: `node tools/generate-server-platform-exercise-seed.mjs --check`
    and `node tools/platform-exercise-focus.mjs --check` pass. A second
    generator run against the same inputs produces no diff.
*   **Server and generator tests**: the Tests list in PR 1.
*   **Repositories against in-memory SQLite**:
    `platform_library_update_test.dart`,
    `exercise_catalog_repository_test.dart`, `erase_all_data_test.dart`.
*   **Sync simulation**: `sync_repository_test.dart`,
    `sync_cycle_runner_test.dart`.
*   **Kill-and-reopen mid-workout**: `platform_library_update_reopen_test.dart`.
*   **Performance**: `performance_budgets_test.dart` passes
    `coldStartHomeInteractiveBudget` and `setSaveConfirmationFrameBudget`, with
    no new budget.
*   **Accessibility**: No screen changes, so no new accessibility tests.
*   **Manual check, before PR 2 merges**: Copy the database of an existing
    install on a physical device, then install the build over it without
    clearing data. Confirm: logged merged exercises appear as user exercises
    with history; a corrected name shows in past Workouts; removed unused
    exercises are gone; a second launch makes no change; and sync still
    completes.

--------------------------------------------------------------------------------

*Drafted with EGM*
