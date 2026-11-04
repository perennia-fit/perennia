# Meal Logging

- **Author:** Leonardo Pinheiro
- **Status:** Approved
- **Date:** 2026-11-02

Related documents:
- [CONTEXT.md](../../CONTEXT.md): ubiquitous language.
- [ARCHITECTURE.md](../../ARCHITECTURE.md): layering, contract spine, sync.
- [AGENTS.md](../../AGENTS.md): invariants and spec requirements.
- [DESIGN.md](../../DESIGN.md): the visual design system.
- Specs this one amends: [unified-food-search.md](unified-food-search.md) (the add-food
  picker becomes part of the Meal screen), [open-food-facts.md](open-food-facts.md) and
  [food-aisles.md](food-aisles.md) (where the picker is opened from).

--------------------------------------------------------------------------------

## Overview

Perennia's users are longevity-focused hybrid athletes who measure what they do to their
body. For them, when a meal was eaten is data: they read eating windows and fasting, and
compare meals with Doses and Workouts when they review a day. They also think about
nutrition in meals. They ate lunch; they didn't eat 140 g of rice and 120 g of chicken
for an app to group.

A Meal is "a single eating occasion with a start instant and optional end" (CONTEXT.md),
the nutrition counterpart of a Workout. This spec makes the Meal the thing the user logs,
and makes its time something the app stores, edits, syncs and validates correctly, for the
app and for agents.

- **One Meal screen** is the whole logging experience, for a new Meal and a saved one.
- **Every Food Entry is saved the moment it is added;** the user is always inside a Meal
  they chose.
- **A Meal gets a frozen UTC offset and a time precision,** and its date follows its time.
- **Agent writes change only what the agent sent,** and agents get the app's operations.

## The Problem

### The user's side

1.  **The time is a side effect.** A Meal's time is the moment the user tapped a Meal Type
    chip (`startMeal` in `nutrition_day_controller.dart`). People often log after eating,
    or at the end of the day, so it is usually wrong. Nothing can change it afterwards. On
    a past day it is wrong twice: the Meal gets that day's `localDate` but today's instant.
2.  **The Meal is a chore, not the subject.** To log anything, the user picks a Meal Type
    under `Start Meal`. An empty Meal appears; they tap `Add food` on its card, search,
    pick and save. A repeat food costs about six taps. A repeat set costs two, which is the
    rule AGENTS.md sets for the gym floor. A stray chip tap leaves an empty Meal, and
    tapping Breakfast twice makes two Breakfasts.
3.  **There is no way to repeat a meal.** The most common repeat is a whole meal ("same
    breakfast as yesterday"), and the user must rebuild it Food Entry by Food Entry.
4.  **Logged Meals can't be fixed.** The repository has operations to change a Portion and
    to delete a Meal or a Food Entry, but no screen calls them.
5.  **The day doesn't read in time order.** The Nutrition Day sorts Meals by Meal Type
    first and time second (`nutrition_day_assembly.dart`), so a 15:00 Breakfast sorts above
    a 12:00 Lunch.
6.  **A food eaten just after a Meal has no quick path.** The fastest way to log from
    Today starts a new Meal. A coffee logged ten minutes after lunch then becomes a second
    Meal, unless the user goes to the Nutrition Day and finds the Lunch card instead.

### The data's side

7.  **The local clock time isn't frozen.** A Meal stores a UTC instant and a time zone
    label taken from `DateTime.timeZoneName`, an abbreviation such as "CET" that can't be
    turned back into an offset. Without a frozen offset, a Meal logged in Lisbon shows a
    different clock time once the user is in São Paulo. Doses solved this with
    `timezoneOffsetMinutes`; Meals never got it.
8.  **There is no rule for editing a time across midnight.** The code has two competing
    models: a Workout keeps its date when its time is edited, and a Dose's date follows its
    new time.
9.  **Imported times are made up.** MyFitnessPal, Cronometer, Yazio and some Lifesum files
    give a date and no time. Their Meals are stored at 00:00 with nothing to mark the time
    as unknown, so a real midnight snack looks the same as "no time recorded".
10. **Agent writes damage Meals.** `batchWriteAgentMeal` (`agent-meal-batch-write.ts`)
    rebuilds the whole Meal row on every call:
    - It stamps the server's current time as `updatedAt` and defaults `deletedAt` to null,
      so an agent adding a coffee to an archived Meal brings it back.
    - It drops import keys from the Food Entries it rewrites.
    - Once Meal times are editable, an agent appending a Food Entry would put back an old
      time over the user's correction.
11. **The contract can't express the new flow.** `entries` requires at least one item, so
    an agent can't create a Meal with no Food Entries yet. `mealType` is required on every
    call. No operation lists the user's Meal Types.
12. **Nothing validates a Meal's time.** No rule in the shared validation module covers
    Meals, and no golden vector does. An agent can send a malformed `localDate` that crashes
    the app when it parses it (`NutritionDayDate.parse`).
13. **Empty Meals and undo are accidents waiting to happen.**
    - Removing a Meal's last Food Entry leaves the Meal behind (`deleteFoodEntry`).
    - Undoing the write that created a Meal archives the Meal but leaves Food Entries added
      later active, so they vanish from every view (`undoBatch`).
14. **Meal and Food Entry sync bypass the shared carry-forward.** `pushMealsInTransaction`
    and `pushFoodEntriesInTransaction` (`sync.ts`) write the pushed payload whole. A key
    added to either payload later is erased by any push that doesn't know it.
15. **Re-import moves Food Entries between Meals.** The importer finds or creates a Meal by
    date and Meal Type (`_findOrCreateImportMeal`). On re-import it rewrites an existing
    entry's Meal, which can pull Food Entries out of a Meal the user edited, bending the
    merge-only rule.

## Goals

### Logging

- **The Meal is what the user logs.** Today's Log action offers **Meal**, which opens the
  Meal screen. The same screen opens from a Meal card. The Start Meal chips are removed
  from the Nutrition Day and from Today's Nutrition view.
- **Every Meal time is chosen by the user or shown as a proposal** on the Meal header.
  - Today, the proposal is `now`, worded as a choice and fixed at the first write.
  - On a past day, there is no proposal: the user must choose a time.
  - On a future day, logging a Meal is not offered.
- **Fast repeats, counted from the moment the Meal screen opens:**
  - Tapping a Your meals row logs the whole meal in one tap, with an Undo bar.
  - A repeat food is the row, then Save, keeping the promise Unified Food Search made.
  - Leaving the screen writes nothing, because every action is already saved.
- **One time choice per Meal,** never one per Food Entry. Food Entries take the Meal's
  time.
- **`Add foods later`** saves a Meal with a time and no Food Entries, shown as
  `add foods`.
- **Your meals** lists the user's repeated meals (Meal History, §5).
  - Two Meals are the same meal when they contain the same set of Foods, whatever the
    Portions.
  - It is ordered by how often the meal was eaten in the last 90 days, then by how
    recently.
  - Tapping a row (Log again) copies the most recent such Meal's Food Entries into the
    Meal being logged, at that Meal's time.
  - It is derived on read, never stored, golden-vectored in Dart and TypeScript, and
    readable by agents.
- **A recent-Meal shortcut** answers Problem 6. On a new Meal today, when the most recent
  timed Meal today started 0 to 30 minutes ago, the screen offers one
  `Add to <time> · <type>` row that switches to that Meal. The app never moves a Food
  Entry by itself.
- **Meal Types are proposed from the clock.** Each seeded Meal Type has a usual time
  window, and the header proposes the type whose window holds the Meal's time. The
  proposal follows the time until the Meal is created, and is then stored like a
  hand-picked type. The user changes it in two taps.
- **Logged Meals can be fixed** from the Meal screen: add or remove Food Entries, change a
  Portion, change the time or Meal Type, or delete (archive) the Meal.
- **The Nutrition Day reads in time order,** each card showing `<time> · <type>`, its Food
  Entries and totals.
- **Logging screens show nutrition only.** No Dose or Workout data, markers or hints
  appear on the Meal screen. Comparing meals with Doses and Workouts happens when the user
  reviews a day, which keeps reading and deciding off the logging path.

### The time model

- **A Meal's time can be set and changed, by the user and by agents.** A repository
  operation and a contract operation do the same thing under the same validation.
- **A Meal's clock time and Nutrition Day are computed from its instant and a stored UTC
  offset,** so they don't change when the device's time zone does.
- **Editing a time across midnight moves the Meal to the matching Nutrition Day.** The
  local date is always derived from the time and the offset, never set on its own.
- **A Meal says whether its time is known.** Date-only imports are stored with date
  precision and shown as `time not recorded`, never as 00:00.
- **A Meal with zero Food Entries is a valid state.** It is created on purpose, or left by
  removing the last entry, an undo, or an agent. It is deleted only by an explicit action.
  CONTEXT.md's Meal definition gains this.

### Agents, validation and integrity

- **An agent write never rewrites a Meal field it didn't send.**
  - It never brings back an archived Meal.
  - It never drops import keys.
  - It never puts back an old time.
  - A write that only adds or changes Food Entries leaves the Meal row untouched.
- **Agents can do what the app does:** create a Meal with no Food Entries, change a Meal's
  time and Meal Type, list the user's Meal Types, and read Your meals.
- **Meal times are validated in the shared two-tier module,** with golden vectors in Dart
  and TypeScript:
  - a hard reject for the impossible (an end before the start, an empty Meal Type);
  - a soft warning for the improbable (a time in the future).
- **No single app action, undo, re-import or agent request leaves an active Food Entry in
  an archived Meal, or moves a Food Entry the user placed.**
- **New Meal and Food Entry keys survive sync** with an app or server that doesn't know
  them, through the existing later-added-key pattern. The server and the app can ship in
  either order.

## Non-Goals

- **Any rule that groups foods into Meals automatically while logging.** The importer's
  existing find-or-create by date and Meal Type stays for first imports, with the reuse
  rule in §7.
- **Meal Types proposed from closeness to a Workout** (Pre-workout, Post-workout). This is
  deferred until a seeded Pre-workout type and a client-side fuelling window exist. The
  first version proposes from clock windows only.
- **Editable Meal Type windows.** The first version uses constant windows for the seeded
  types. Custom types have no window and are only chosen by hand.
- **A note on `Add foods later` Meals.**
- **Per-Food-Entry eaten-at times.** A Meal's time is its start, and its Food Entries
  inherit it. A per-item time can be added later without changing this model.
- **Writing or showing `endedAt`.** The column stays and keeps its meaning; the app never
  sets it.
- **Eating-window, fasting or any other analytics** on Meal times. They need their own
  golden-vectored spec.
- **Cross-domain fuelling analytics keep counting `date` Meals as they do today;**
  excluding them is a separate analytics change.
- **Planned or future meals, photo logging, and a cross-domain review timeline.**
- **Field-level conflict resolution in sync.** Last-writer-wins stays per row (see Risks
  and Mitigations).
- **Inferring offsets or precision for existing Meals.** Existing Meals stay `instant`
  with a null offset (§1).
- **Storing the device's IANA zone name.** The app keeps writing the zone abbreviation, as
  Doses and Workouts do; the offset is what every reader uses.
- **Changes to Meal Types themselves:** ids instead of names, or rename behaviour.
- **Any use of Dose data,** for display or for proposals. The Protocols domain sits behind
  a PIN or biometric lock.

## Open Questions

- None. The decisions a reviewer is most likely to challenge are collected in §13.

## Critical User Journeys (CUJs)

### CUJ 1: Log a repeat meal now

- **Given**: It is 12:40 today. The user ate the same chicken-and-rice lunch twice in the
  last week.
- **When**: They tap Today → Log → Meal, then tap that lunch in Your meals.
- **Then**:
  - The header reads `now · Lunch` before the tap.
  - After the tap, one Meal at 12:40 with both Food Entries exists, written in one Batch.
  - An Undo bar is shown; undo removes the Meal and its Food Entries together.
  - Leaving the screen writes nothing more.

### CUJ 2: Log one food now

- **Given**: The user is eating a yoghurt at 16:05 today.
- **When**: Log → Meal → tap the yoghurt in Your foods → Save on the Portion screen.
- **Then**:
  - A Snack Meal at 16:05 exists with one Food Entry, created in one transaction.
  - The Meal screen now shows that saved Meal.

### CUJ 3: End-of-day review

- **Given**: At 21:40 the user hasn't logged breakfast (07:30) or lunch (12:30).
- **When**: They open Log → Meal, tap the header, set 07:30, and add three foods; then
  open Log → Meal again, set 12:30, and add two foods.
- **Then**:
  - Two Meals exist, at 07:30 (proposed type Breakfast) and 12:30 (Lunch).
  - Each Meal took one time choice; every food took the row, then Save.
  - The Nutrition Day lists them in time order.

### CUJ 4: Capture now, add foods later

- **Given**: The user eats lunch at 13:10 at a restaurant and has no time to search.
- **When**: Log → Meal → `Add foods later`.
- **Then**:
  - A Lunch Meal at 13:10 with no Food Entries exists. Its Nutrition Day card reads
    `13:10 · Lunch · add foods`.
  - That evening, tapping the card opens the Meal screen. Food Entries added there join
    that Meal at 13:10.

### CUJ 5: Back-fill a past day

- **Given**: The Nutrition Day shows yesterday.
- **When**: The user taps `Log meal`.
- **Then**:
  - The time sheet opens by itself; the header reads `Choose time`.
  - Nothing is written until a time is chosen and a food is saved or `Add foods later` is
    tapped.
  - The Meal's date is yesterday, derived from the chosen time and the frozen offset.

### CUJ 6: Fix a Meal's time across midnight

- **Given**: A Meal logged at 23:50 on Monday, offset +01:00.
- **When**: The user opens it, taps the header, and picks Tuesday and 00:10.
- **Then**:
  - The Meal moves to Tuesday's Nutrition Day. Its offset stays +01:00.
  - One Activity Log entry records the change.

### CUJ 7: An agent adds a coffee to a corrected Meal

- **Given**: The user changed an active Meal's time from 21:40 to 12:30 on the phone, and
  it synced.
- **When**: An agent calls `batchWriteAgentMeal` with that Meal's id, no other Meal fields,
  and one new entry.
- **Then**:
  - The Food Entry is added. The Meal row is not rewritten: its time stays 12:30.
  - Had the Meal been archived, the request would have been rejected with
    `meal_archived`.

### CUJ 8: Imported days

- **Given**: A MyFitnessPal file with date-only rows.
- **When**: The user imports it, then imports it again after adding a food to one of the
  imported Meals.
- **Then**:
  - The imported Meals show `time not recorded`, not 00:00.
  - The second import adds nothing that was already there, and never moves a Food Entry
    out of the Meal the user edited.

### CUJ 9: Add a coffee to the lunch just logged

- **Given**: The user logged a 12:30 Lunch from Your meals at 12:40. At 12:55 they have a
  coffee.
- **When**: They tap Today → Log → Meal.
- **Then**:
  - The new Meal screen shows `Add to 12:30 · Lunch` above Your meals.
  - Tapping it switches to the Lunch Meal's screen; the coffee saved there joins Lunch.
  - Had they ignored the row, the coffee would have started a new Meal at 12:55.

### CUJ 10: Fix a logged Meal

- **Given**: A saved Dinner with rice, chicken and a Quick Entry for a dessert.
- **When**: The user opens it from its card, taps the rice and changes its Portion, removes
  the chicken and the dessert, then uses Delete meal.
- **Then**:
  - The Portion change and each removal are one Batch each, with an Undo bar.
  - Removing the last Food Entry leaves the Meal, shown as `add foods`.
  - Delete meal asks for confirmation, then archives the Meal; the screen closes.
- **And when** the user had instead tried to undo the Batch that created the Meal after
  adding the dessert, the undo is refused with
  `Can't undo: foods were added to this meal afterwards.`

## Technical Plan (Architecture)

The change keeps the existing architecture: widgets call controllers, controllers call
repositories, and only repositories touch Drift or the network (ARCHITECTURE.md).

```text
 Today Log ▸ Meal ──┐                                 ┌── Meal card (any day)
 Log meal button ───┤                                 │
                    ▼                                 ▼
        ┌──────────────────── MealScreen ────────────────────┐
        │ header: time · Meal Type    (MealTimeSheet)        │
        │ recent-Meal shortcut  |  Your meals (Meal History) │
        │ Your foods + search (AddFoodPicker, embedded)      │
        │ the Meal's Food Entries  |  Add foods later        │
        └───────────────┬────────────────────────────────────┘
                        │ MealScreenController (Riverpod)
                        ▼
   NutritionRepository: logFoodEntrySnapshot(target) · logQuickEntry(target)
     logMealAgain · createMeal · updateMealTime · updateMealType · listMealHistory
                        │ one transaction + one Batch per user action
                        ▼
   Drift: meals (+ timezone_offset_minutes, time_precision) · Activity Log
                        │ sync push/pull (Activity Log images)
                        ▼
   Server: pushMealsInTransaction (opaque-row adapter) · batchWriteAgentMeal (partial)
     listAgentMealTypes · listAgentMealHistory · shared Meal-time validation
```

### 1. The Meal time model

**New columns on `meals`** (Drift schema 64 → 65, using the guarded `addColumn` pattern
of the earlier steps; `main` is at 64 as of release 0.2.0):

| Column | Type | Meaning |
|---|---|---|
| `timezone_offset_minutes` | int, nullable | The UTC offset frozen when the Meal's time was set, the same rule as `doses.timezoneOffsetMinutes`. Null only on Meals written before this change, and on agent writes whose zone the server can't resolve (§9). |
| `time_precision` | text, not null, default `'instant'` | `instant`: `started_at` is the time the user ate. `date`: only the date is known; `started_at` is local midnight of `local_date` and is never shown as a clock time. |

**The frozen offset** is `startedAt.toLocal().timeZoneOffset.inMinutes`: the device zone's
offset at the Meal's own instant, not at the moment of logging. `_createMeal` and
`updateMealTime` compute it when the caller doesn't pass one. That covers new Meals, past
days, imports and a legacy Meal's first retime, and it keeps a summer Meal back-filled in
winter on its own day.

**`timezone`** keeps its current value: the app writes `startedAt.toLocal().timeZoneName`,
an abbreviation, as Doses do. The offset, not the label, is what every reader uses.

**The local date is always derived, never set on its own.**

- `local_date = calendar date of (started_at + timezone_offset_minutes)`.
- `clockAtOffset` moves unchanged from `lib/domain/protocols/protocols.dart` to a shared
  `lib/domain/common/local_clock.dart`, next to a new `localDateAtOffset(DateTime instant,
  int? offsetMinutes)` that returns a `({int year, int month, int day})` record, so common
  code doesn't depend on nutrition types. A null offset uses the device zone, as
  `clockAtOffset` does. Nutrition code wraps the record in a `NutritionDayDate`.
- `localDateAtOffset` is the single rule that writes `meals.local_date` in the app.
- On the server, `apps/server/src/timezone.ts` gains the twin,
  `localDateAtOffset(instant: Date, offsetMinutes: number): string` (`YYYY-MM-DD`). The
  golden vector `m39` (§8) pins both languages.

**Editing a Meal's time follows the Dose model** (`_editDose`):

- The stored offset is kept, and `local_date` is recomputed, so 23:50 → 00:10 moves the
  Meal to the next Nutrition Day.
- A legacy Meal with a null offset freezes the offset at its new instant, by the rule
  above.
- Setting a time on a `date` Meal makes it `instant`.

**Existing rows** keep `timezone_offset_minutes = null` and `time_precision = 'instant'`.
Readers use the device zone for a null offset, as they do for legacy Doses. No existing
time, date or precision is changed; Meals imported before this change keep showing their
stored local midnight, as they do today (§13, decision 6).

**New imports:** `NutritionImportMeal` gains a named parameter `timePrecision`, defaulting
to `instant`. Each adapter sets `date` when the source row carries no time of day:

- MyFitnessPal: always `date` (its export has a date column only).
- Cronometer: `date` when the `Time` column is absent or empty for the row.
- Yazio and Lifesum: `date` when the parsed date text has no time component.

`_createMeal` stores the import's precision, and a `date` import's `started_at` stays local
midnight, as the adapters already produce it.

### 2. A Meal with zero Food Entries

- A Meal with no active Food Entries is valid. It arises from `Add foods later`, removing
  the last entry, an undo, an agent write, or an older stray Start Meal tap.
- The UI shows every such Meal the same way, as `add foods`.
- `deleteFoodEntry` already leaves the Meal in place; that becomes the specified behaviour.
- Deleting the Meal is always explicit, through the existing `deleteMeal`.

### 3. Logging writes (NutritionRepository)

Every user action is one transaction and one Batch, so undo works per action and a crash
can't leave half an action behind.

**`MealTarget`** is a sealed class in `lib/domain/nutrition/nutrition.dart`:

- `ExistingMealTarget(String mealId)`: an existing Meal.
- `NewMealTarget(PendingMeal meal)`: a Meal the same write creates.

**`PendingMeal`** has `String id` (minted when the Meal screen opens), `DateTime?
startedAt` (null means now) and `String? mealTypeName` (null means proposed). The
repository resolves both inside the write transaction: a null `startedAt` becomes the
clock time of the write, and a null `mealTypeName` becomes `proposeMealType` (§4) at that
time. So the stored time is the time of the write, not the time the screen opened.

| Method | Writes | Used by |
|---|---|---|
| `logFoodEntrySnapshot({required MealTarget target, required FoodEntrySnapshotDraft entry})` (changed) | Adds a Food Entry. A `NewMealTarget` creates the Meal in the same transaction and Batch. Returns the existing `LogFoodEntryResult`. | Save on the Portion screen |
| `logQuickEntry({required MealTarget target, required QuickFoodEntryDraft entry})` (changed) | The same for a Quick Entry. Returns the existing `LogQuickEntryResult`. `logQuickEntryForMeal` is removed. | Quick Entry |
| `logMealAgain(String sourceMealId, MealTarget target)` (new) | Copies the source Meal's active Food Entries by the copy rule below, in one Batch. Returns `LogMealAgainResult(batchId, mealId, foodEntryIds, warnings)`. | Your meals row |
| `createMeal(PendingMeal meal)` (changed) | Creates a Meal with no Food Entries. Returns the Meal id, as today. | `Add foods later` |
| `updateMealTime(String mealId, DateTime startedAt) → Future<String>` (new) | The Dose-model time edit from §1, and `time_precision = 'instant'`. Returns the Batch id. | Header on a saved Meal |
| `updateMealType(String mealId, String mealTypeName) → Future<String>` (new) | Stores the Meal Type name. Returns the Batch id. | Header on a saved Meal |
| `listMealHistory({DateTime? now, int limit = 20}) → Future<List<MealHistoryRecord>>` (new) | Nothing: the Meal History read from §5. | Your meals |
| `deleteFoodEntry`, `updateFoodEntryPortion`, `deleteMeal` (existing, unchanged) | As today. | Remove an entry, edit a Portion, Delete meal |

Rules shared by the writes:

- An `ExistingMealTarget` whose Meal is archived is rejected, as today.
- The entry draft's `mealId` must equal the target's Meal id; a mismatch throws
  `ArgumentError`.
- **Double tap.** A `NewMealTarget` whose id already exists throws
  `MealAlreadyExistsException` and writes nothing. The controller ignores taps while a
  write is in flight, and on that exception switches to the saved state.
- `MealDraft` loses `localDate` (the date is always derived) and gains
  `timezoneOffsetMinutes` and `timePrecision`; it already has `timezone`. `_createMeal`
  uses `localDateAtOffset` and `validateMealTime` (§8) in place of its ad-hoc checks.

**The `logMealAgain` copy rule,** for each source entry in source order:

- A Food Entry of a User Food that is still active, whose source Portion is still allowed
  for that Food, is re-read through the `logFoodEntry` path, so the user's own edits to
  the Food apply.
- Every other Food-backed entry (USDA, Open Food Facts, an archived User Food, a Portion
  no longer allowed) copies its stored snapshot, through the `logFoodEntrySnapshot` path.
- A Quick Entry is copied as a Quick Entry.
- Import keys (`import_source`, `import_external_id`) are never copied, so a later re-import
  can't treat the copies as already imported.
- The copies take the target Meal's time.

**`startMeal` until stage 3.** Stage 2 keeps `startMeal` working: it builds `startedAt` as
the selected day at the current clock time (or now on today), so a Meal started on a past
day lands on that day. Stage 3 removes it.

### 4. Meal Type proposals

- A pure function `proposeMealType(localClock, mealTypes)` in
  `lib/domain/nutrition/meal_type_proposal.dart` picks a Meal Type from the Meal's local
  clock time, compared by minute.
- The windows are constants keyed by seed id, so a renamed seeded type keeps its window and
  the proposal stores its current name:

  | Seed id | Window |
  |---|---|
  | `meal-type-breakfast` | 04:00–10:29 |
  | `meal-type-lunch` | 10:30–14:59 |
  | `meal-type-dinner` | 17:00–21:59 |
  | `meal-type-snack` | every other time |

- If the matching seeded type is archived, the proposal is the Snack type. If that is
  archived too, it is the first active type by sort order. With no active type at all, the
  proposal stores the label `Snack`.
- Custom Meal Types have no window, so they are never proposed; the user picks them.
- **Lifecycle:**
  - While the Meal is unwritten, the proposal follows the header time.
  - At the first write, the proposed type's current name is stored in `meals.meal_type`,
    exactly as a hand-picked type is.
  - It is never recomputed after that. A stored proposed type is a label the user saw and
    could change, not a cached derived value.
- Agents and imports never call it: they send or carry their own Meal Type.

### 5. Meal History (Your meals)

A new derived read, built the same way as Food History (`listFoodHistory`), with the same
filters, window and time rules.

- **Rows considered:**
  - active Food Entries with `entry_kind = 'food'` and non-null `food_source`, `food_id`
    and `is_liquid`, excluding entries of archived User Foods;
  - in active Meals with `time_precision = 'instant'` and `started_at >= now − 90 days`,
    inclusive;
  - the 90 days are one shared Dart constant, `foodHistoryWindow = Duration(days: 90)`,
    extracted from the inline value in `listFoodHistory`.
- **Qualifying Meal:** its considered rows hold two or more distinct Foods. Quick Entries
  don't count toward a Meal's identity, and don't stop it qualifying.
- **Identity:** the distinct `food_source:food_id` keys, sorted in ordinal (byte) order and
  joined with `|`. That string is the canonical string; ids are ASCII. Portions don't
  count.
- **Item:**
  - its Foods in canonical order, each with `foodSource`, `foodId` and `name` (the snapshot
    name from the most recent Meal with that identity);
  - `count`, the number of qualifying Meals with that identity;
  - `lastMealId` and `lastStartedAt`, from the most recent such Meal. That Meal is the
    source `logMealAgain` copies, Portions and Quick Entries included.
- **Order:** `count` descending, then `lastStartedAt` descending, then the canonical string
  ascending. At most `limit` items (20 in the app).
- **App:** `NutritionRepository.listMealHistory` is one SQL query shaped like
  `listFoodHistory`: a CTE for the considered rows, `group_concat(key, '|' ORDER BY key)`
  per Meal, then grouped by identity with `ROW_NUMBER` to pick the latest Meal. It returns
  `MealHistoryRecord`s. The Meal screen reads it once when it opens; Your meals shows only
  while the Meal has no Food Entries, so it never needs to refresh after a write.
- **Server:** a pure `buildMealHistory(rows, {now, limit})` in
  `apps/server/src/meal-history.ts`. A Meal payload without `time_precision` reads as
  `instant`.
- **It is computed on read and never stored or synced.** A new golden vector,
  `m38-meal-history.json`, pins both languages. Dart runs it through the repository against
  in-memory SQLite, as m37 does for Food History.

### 6. The Meal screen

**Entry points:**

- Today's Log sheet item becomes **Meal** (`homeLogMeal`). It opens the Meal screen for the
  selected day instead of pushing the Nutrition Day.
- The Nutrition Day and Today's Nutrition view replace their Start Meal chips with one
  `Log meal` button. Manage Meal Types and Edit goals stay.
- On a future day, the Log sheet's Meal item and the `Log meal` button are hidden.
- Tapping a Meal card on any day opens the Meal screen in its saved state. The cards' own
  `Add food` button and its picker sheet are removed.

**It is a full-screen route**, `MealScreen` in
`lib/features/nutrition/widgets/meal_screen.dart`, driven by `MealScreenController`, an
`AutoDisposeNotifier` family keyed by `MealScreenArgs.newMeal(NutritionDayDate day)` or
`MealScreenArgs.existing(String mealId)`. `MealScreen` has matching `MealScreen.newMeal`
and `MealScreen.existing` constructors.

| State | Header | Body | Actions |
|---|---|---|---|
| New, today | `now · <proposed type>` | Recent-Meal shortcut (if eligible), Your meals, Your foods and search | `Add foods later`; any pick writes the Meal |
| New, past day | `Choose time`; the time sheet opens on entry | As above, with picking disabled until a time is chosen | `Add foods later`, enabled once a time is chosen |
| Saved, with entries | `<time> · <type>` | The Meal's Food Entries, then Your foods and search | Remove an entry, edit a Portion, Delete meal |
| Saved, no entries | `<time> · <type> · add foods` | Your meals, Your foods and search | Delete meal |

A saved `date`-precision Meal uses the matching saved row, with `time not recorded` in
place of `<time>`. Choosing a time makes it `instant`.

**Behaviour:**

- **The time sheet,** `MealTimeSheet`, reuses the Dose edit pattern
  (`protocols_day_view.dart`): a date picker capped at today, a time picker read at the
  Meal's offset (the device zone for a new Meal), and the Meal Type list.
  - **Time-shift buttons** `−15 min`, `−30 min` and `−1 h` show only while the Meal is on
    today. Each sets the time to the current clock minus that amount, replacing any
    earlier choice, so they don't stack. A result before midnight moves the Meal to the
    previous Nutrition Day, as any time change does.
  - **Future times.** The sheet asks for confirmation exactly when the shared validator
    warns (§8: more than 5 minutes ahead). Dates after today can't be picked.
  - **The sheet header** shows the date when the chosen date is not the day the screen
    was opened for.
  - On a new Meal, choices stay on screen until the first write. On a saved Meal, each
    change is one `updateMealTime` or `updateMealType` call.
- **Your meals** shows only while the Meal has no Food Entries. Tapping a row calls
  `logMealAgain` and shows an Undo bar for that Batch.
- **The recent-Meal shortcut** shows only on a new Meal, today. The eligible Meal is the
  most recent active `instant` Meal on today, with or without entries, whose start is
  between 0 and 30 minutes before now, inclusive. `date` Meals and future starts never
  qualify. Its row reads `Add to <time> · <type>`; tapping it replaces the screen with that
  Meal's screen.
- **The add-food picker is embedded,** not opened as a sheet. `AddFoodPicker` and
  `add_food_controller.dart` replace the required `MealRecord meal` with a `MealTarget`.
  Selecting a Food opens `LogPortionScreen`, which takes the `MealTarget`, calls
  `logFoodEntrySnapshot`, and pops with the saved Meal id. The Quick Entry write moves to
  the same split in the picker and its controller.
- **Entries.** Each Food Entry row has a 48 dp remove button that calls `deleteFoodEntry`,
  with an Undo bar. Tapping a Food-backed entry without import keys opens
  `LogPortionScreen` prefilled, and its Save calls `updateFoodEntryPortion`. Imported
  entries and Quick Entries are remove-only.
- **Removing the last entry keeps the Meal.** The screen moves to the "no entries" state.
- **Delete meal** sits in the app bar's overflow menu. It asks for confirmation, then calls
  `deleteMeal`, which archives the Meal and its Food Entries in one Batch, so one undo
  restores all of it. The screen then closes.
- **After undoing a new Meal's first action** from the Undo bar, the screen returns to the
  new-Meal state with a fresh pending id.
- **A refused undo** shows the shared undo-conflict message (§7).
- **Nothing on this screen reads or shows Dose or Workout data.**

**The Nutrition Day order** (`nutrition_day_assembly.dart`) becomes:

1. `date` Meals first, by Meal Type sort order. They have no clock time.
2. Then `instant` Meals by local clock time.
3. Ties break by `id`.

The Meal Type sort-order lookup stays only for `date` Meals.

### 7. Integrity: undo, re-import, archived Meals

- **Undo.** An undo is refused when the Batch creates a Meal and an active Food Entry in
  that Meal was created by a different Batch. Updates by other Batches to an entry the
  undone Batch created don't count; the existing stale check covers those.
  - **App:** `undoBatch` gains `_mealDependentUndoConflicts` after the existing
    template-group check. It reports `ActivityLogUndoConflictReason.dependent`, and nothing
    is applied, following undo's existing all-or-nothing rule.
  - **Server:** `undoAgentActivityBatch` (`agent-activity.ts`) gains the same check in its
    pre-check pass, with a new conflict outcome `skipped_dependent` on the Meal's entry.
    As with `skipped_stale`, nothing is applied.
  - **Message:** `_undoConflictMessage` moves to
    `lib/features/activity/undo_conflict_message.dart` and handles `dependent` with
    `Can't undo: foods were added to this meal afterwards.` The Activity feed and the Meal
    screen share it.
- **Re-import.**
  - `_findOrCreateImportMeal` runs only when an import creates a Food Entry. An updated
    entry stays in `existing.mealId`, which is recorded in `landedMealIds`, and
    `_updateImportedFoodEntry` drops its `mealId` parameter.
  - An import reuses an existing Meal only if it has at least one active Food Entry and
    every active Food Entry in it carries an `import_source` (from any source). Candidates
    are the active Meals on that date with the stored Meal Type, ordered by `started_at`,
    then `id`; the first that passes is used, otherwise a new Meal is created. A Meal the
    user created, or added a food to, is never reused.
- **Archived Meals.**
  - The app already rejects writing a Food Entry into an archived Meal.
  - The agent write gains the same rule (§9): `meal_archived`.

### 8. Validation

Three Meal rules join the shared two-tier module: Dart in
`lib/domain/nutrition/meal_validation.dart`, TypeScript in `agent-validation.ts`. Both run
on every app and agent Meal write, against the Meal as it will be stored.

| Rule | Tier | Condition |
|---|---|---|
| `meal_ended_before_start` | Hard reject | `endedAt` is not after `startedAt`. This replaces the ad-hoc `ArgumentError` in `_createMeal`. |
| `meal_type_required` | Hard reject | The Meal Type label is empty. This replaces the ad-hoc check. |
| `meal_time_in_future` | Soft warning | `startedAt` is more than 5 minutes after `now`. |

Input shape is checked by the agent request schema, as the Dose write does, and fails with
a 400: the offset range through `AGENT_PROTOCOLS_MIN_OFFSET_MINUTES` and
`AGENT_PROTOCOLS_MAX_OFFSET_MINUTES` (−720 to +840), and the `localDate` format through
`LocalDateSchema` (both in `agent-protocols.ts`). In the app the offset comes from the
device and the date is derived, so neither can be malformed.

- **Dart:** `validateMealTime(MealTimeInput input, {required DateTime now}) →
  MealValidationResult`, with `MealTimeInput(startedAt, endedAt?, mealType)`, shaped like
  `dose_validation.dart`.
- **TypeScript:** `validateAgentMealTime(input, {now})`, exported from
  `apps/server/src/index.ts`.
- **Golden vector `m39-meal-validation.json`,** domain `meal-validation`, with `schema` and
  `schemaVersion`. Each case is `{name, input: {startedAt, endedAt?, mealType,
  timezoneOffsetMinutes, now}, expected: {accepted, warningRules, errorRules, localDate}}`.
  Runners assert the rules and that `localDateAtOffset(startedAt, offset)` equals
  `expected.localDate`, including offsets that cross midnight in both directions.

### 9. Agent surface

**Capabilities and their operations:**

| App capability | Agent operation |
|---|---|
| Log a food, a Quick Entry, or Log again into a new or existing Meal | `batchWriteAgentMeal` with the Meal and its entries |
| `Add foods later` | `batchWriteAgentMeal` with Meal fields and no entries |
| Change a Meal's time or Meal Type | `batchWriteAgentMeal` with `startedAt` (and its offset or zone) or `mealType` |
| Remove a Food Entry, edit a Portion | `batchWriteAgentMeal` with the full entry, `deletedAt` set or the new Portion |
| Delete meal | `batchWriteAgentMeal` with `meal.deletedAt` |
| Your meals | `listAgentMealHistory` |
| The Meal Type list | `listAgentMealTypes` |
| Undo | `undoAgentActivityBatch` (existing), with `skipped_dependent` |

**`batchWriteAgentMeal`** (`POST /agent/meals/batch-write`, MCP `agent_batch_write_meal`)
writes only the Meal fields a request sends.

**Contract diff:**

- `meal.mealType`, `meal.startedAt`, `meal.timezone` and `meal.localDate` become optional.
- New optional fields: `meal.timezoneOffsetMinutes` (int, −720 to +840) and
  `meal.timePrecision` (`instant` | `date`).
- `meal.endedAt`, `meal.deletedAt` and the entry `deletedAt` lose their `.default(null)`.
- `entries` allows 0 items. Entries otherwise keep today's shape and required fields.
- A schema refinement rejects, with a 400, a request with no Meal fields besides `id` and
  no entries, and a time block that breaks the rules below.
- `meal.timezone` is described as "The Meal's time zone as entered: an IANA name lets the
  server derive the offset; any other label is stored for display only."
- The issue schema's `itemIndex` and `entryId` become nullable (null for Meal-level
  issues). The 200 response gains a top-level `warnings` array for Meal-level warnings.
- New error codes: 409 `meal_id_conflict` and `entry_id_conflict`; 422
  `entry_meal_mismatch`, `meal_archived`, `meal_create_incomplete` and
  `meal_offset_unknown`; 404 `meal_not_found`.

**Field rules:**

- **Meal fields.** `meal.id` is required. `mealType`, `endedAt`, `deletedAt` and
  `timePrecision` may each be sent on their own: an absent field keeps the stored value,
  and `null` clears `endedAt` or `deletedAt`. `mealType` is stored as the name sent, as
  the app stores it.
- **Time block.** `startedAt` is sent together with `timezoneOffsetMinutes`, a `timezone`,
  or both; `timezoneOffsetMinutes` and `localDate` are never sent without `startedAt`. The
  offset is resolved in this order:
  1. the sent offset;
  2. else `offsetMinutesInTimezone(timezone, startedAt)` (`timezone.ts`);
  3. else `null`.

  Then:
  - With a known offset, `localDate` is derived (§1), and a supplied one is ignored.
  - With a null offset (an abbreviation such as `BRT`, as agents send today), the
    supplied `localDate` is required and stored, as the Dose write does
    (`doseTimezoneOffsetMinutes`). Without one the request fails with 422
    `meal_offset_unknown`.
  - Sending `startedAt` sets `timePrecision` to `instant` unless `timePrecision` is also
    sent. For `date`, the agent sends local midnight, as the importers do.
  - The stored `timezone` is the sent value; when only an offset is sent, it is the label
    `UTC±hh:mm`.
- **Create** happens when the id doesn't exist. It needs `mealType` and the time block;
  without them the request fails with 422 `meal_create_incomplete`. A request that carries
  only `id` and entries for an id that doesn't exist fails with 404 `meal_not_found`. A
  Meal id that exists for another user fails with 409 `meal_id_conflict`.
- **Entries-only request** (`meal` carries only `id`): the Meal row is not rewritten, and
  its `updatedAt` doesn't move.
- **Archived Meals.** A request whose resulting Meal is archived may not add Food Entries
  or un-archive them: 422 `meal_archived`. A request that sends `deletedAt: null` and
  entries un-archives the Meal and writes the entries.
- **Entries** are written as sent, except that an unsent `deletedAt` keeps the stored
  value, and the import keys, which are never in an agent payload, are carried forward
  from the stored payload (§10). An existing entry id under a different `meal.id` fails
  with 422 `entry_meal_mismatch`; an entry id owned by another user fails with 409
  `entry_id_conflict`.
- **Validation** runs the three §8 rules on the Meal as it will be stored. Hard rejects
  are 422 with Meal-level issues; the warning is returned in `warnings`.

**Pipeline.** `AgentMealBatchWriteStore.writeMealBatch` opens the transaction and takes the
idempotency check, as today. It then selects the stored Meal and entry payloads (by id, for
any user) with `FOR UPDATE`, calls the pure
`prepareAgentMealBatchWrite(request, stored, now)`, and either writes the prepared rows or
returns the issues and status. A prepared Meal row of `null` means "not rewritten". REST
(`app.ts`) and MCP (`agent-mcp.ts`) both call the store this way.

**New reads:**

- `listAgentMealTypes` (`GET /agent/meal-types`, MCP `agent_list_meal_types`), in a new
  `agent-meal-types.ts` with its own store: `{ mealTypes: [{ id, name, sortOrder }] }`,
  active types only, ordered by `sortOrder` then `id`.
- `listAgentMealHistory` (`GET /agent/meals/history`, MCP `agent_list_meal_history`), in
  `agent-meal-history.ts`: query `limit`, default 20, maximum 50. Response
  `{ items: [{ foods: [{ foodSource, foodId, name }], count, lastMealId, lastStartedAt }] }`,
  from `buildMealHistory` (§5).

**Existing read:** `listAgentMeals` adds `timezoneOffsetMinutes` and `timePrecision` to
`AGENT_MEAL_LIST_FIELDS` and `AgentMealListItemSchema`, in the default field set. Payloads
written before this change return `null` and `instant`.

The MCP tools are hand-registered in `agent-mcp.ts`, so each gets its input schema there.

### 10. Sync

Meals and Food Entries follow the repository's later-added-key pattern.

1. **Server:** add `[MEALS_SYNC_ENTITY]: ["timezone_offset_minutes", "time_precision"]`
   and `[FOOD_ENTRIES_SYNC_ENTITY]: ["import_source", "import_external_id"]` to
   `SYNC_CARRY_FORWARD_PAYLOAD_KEYS` (`sync.ts`). Re-implement `pushMealsInTransaction`
   and `pushFoodEntriesInTransaction` as `readExisting`/`writeRow` adapters over
   `pushOpaqueSyncRowsInTransaction`, as `pushProtocolSkipsInTransaction` is. That carries
   the keys into the stored payload and both Activity Log images.
2. **App decode:** `_mealCompanionFromImage` reads both Meal keys with the
   `_imageStringIfPresent` pattern, plus an int twin. An absent key leaves the column
   untouched on update and falls to the column default on insert. When a stored
   `local_date` is malformed, it re-derives `local_date` from `started_at` and the offset
   with `localDateAtOffset`, so a bad server row no longer crashes pull.
3. **App undo:** add `AppDatabase.mealsTable: {'timezone_offset_minutes': null,
   'time_precision': 'instant'}` to `_activityLaterAddedKeyDefaults`, so undo doesn't treat
   a pre-upgrade image as stale.
4. **Order:** either order works. A server without this change keeps the keys it doesn't
   know in the payload; a push from an app without this change, and an old image, leave
   them as stored.

Last-writer-wins stays per row (`lwwWins`).

### 11. Invariants

| Invariant | Effect |
|---|---|
| A Workout is a session | Preserved and extended. A Meal stays a session with its own instant. The Nutrition Day remains derived, and its date is now always derived from the Meal's time by `localDateAtOffset`, the single rule that writes `local_date`. |
| Sets (and Food Entries) are self-describing | Preserved. Log again copies snapshots, or re-reads an active User Food into a new snapshot. A Meal Type is stored as the name the user saw. |
| Derived analytics are computed, never stored | Preserved. Meal History is derived on read. The stored proposed Meal Type is a visible, editable label fixed at creation, not a cache. Nothing recomputes it. |
| User-facing delete = archive; no cascading deletes | Preserved. Delete meal archives the Meal and its Food Entries in one Batch that one undo restores, which is the existing `deleteMeal`. Removing the last entry never deletes the Meal. |
| Restore/import is merge-only | Strengthened. Re-import no longer moves Food Entries, and imports no longer reuse user-made Meals. Archive restore decodes pre-v65 Meals through a shim that defaults `timePrecision` (stage 2). |
| Local writes never block on the network | Preserved. Every action is one local transaction, with no platform call. |
| Sync is silent last-writer-wins with recoverable losers | Preserved. Per-row LWW is unchanged. Agent writes stop rewriting unsent fields, which removes a source of silent reverts but not LWW itself. |
| Validation is one shared two-tier module | Extended with three Meal rules and a golden vector in both languages. |
| No behavioural analytics | Untouched. |

### 12. New and changed CONTEXT.md terms

- **Meal (changed):** "…with a start instant, a frozen UTC offset, and a time precision.
  Its Nutrition Day is derived from its time and offset, so changing the time can move it
  to another day. A Meal with no Food Entries is valid."
- **Time Precision (new):** "Whether a Meal's start is the time the user ate (instant) or
  only its date is known (date), as with date-only imports. A date-precision Meal never
  shows a clock time."
- **Meal History (new):** "The distinct meals a user repeats, derived from their active
  timed Meals in the last 90 days that contain two or more distinct Foods. Two Meals are
  the same meal when they contain the same set of Foods, whatever the Portions; Quick
  Entries don't count. Ordered by count, then recency. Computed, never stored. Shown as
  'Your meals'."
- **Meal Type (changed):** "…The seeded types have a usual time window used to propose a
  type for a new Meal."

### 13. Decisions open to challenge

1. **The undo of a Meal's creation is refused** when later Food Entries depend on it. The
   alternative was a partial undo (Alternative G).
2. **Quick Entries don't count toward Meal History identity.** A Quick Entry has no Food
   identity to compare. Log again still copies them.
3. **A legacy Meal's offset is frozen on its first retime,** as Doses do.
4. **The constant time windows** in §4. They follow common meal times. The gap from 15:00
   to 16:59 falls to Snack on purpose: a meal at that hour is usually a snack.
5. **The future-time warning threshold** of 5 minutes absorbs clock drift between devices
   and the seconds between opening the sheet and saving.
6. **No backfill of existing imported Meals.** No store release exists, so the only
   affected data is Meals already imported on development devices. They keep showing
   their stored local midnight, as they do today. A deterministic backfill rule is
   Alternative N.
7. **Agent requests with only a zone abbreviation** store a null offset and the supplied
   `localDate`, as the Dose write does, so no agent call that works today starts failing.
8. **The time-shift buttons** stay in the first version, because they make end-of-day
   review quick. Cutting them leaves the date and time pickers.
9. **The recent-Meal shortcut** stays, because it answers Problem 6. Cutting it removes
   the goal, the screen state, the controller state, the string and the tests.

## Risks and Mitigations

- **Rollback.** The schema change is additive, and an older app ignores the columns. The
  server change is backward compatible: older apps' pushes keep the new keys as stored
  (§10), and their agent reads ignore the new fields.
- **Agent write security.** A Meal or entry id owned by another user fails with 409; an
  entry moved to another Meal fails with 422. Un-archiving with `deletedAt: null` is a
  power agents already have.
- **Last-writer-wins.** Concurrent devices can still leave an active Food Entry in an
  archived Meal under per-row LWW, for example one device deleting a Meal while another
  adds to it offline. The losing version is recoverable through the Activity Log
  (Alternative I).
- **Agent compatibility.** Requests that send only a zone abbreviation keep working
  through the null-offset path (§9). The only requests that start failing are the
  conflict and mismatch cases, which were silent data damage.
- **Imported data.** Meals imported before this change keep their stored local midnight
  and read as `instant` (§13, decision 6).

## Alternatives Considered

### Alternative A: Food-first logging with automatic grouping

The user logs a food, and the app files it into a Meal: a food within 15 minutes of an
existing Meal joins it, otherwise it starts a new one. The 15-minute rule comes from the
neutral eating-occasion definition used in nutrition research.

- **Pros**: One fewer concept on screen; the user never thinks about Meals while logging.
- **Cons**:
  - People think in meals, so the app's guess is the wrong mental model.
  - It needs a span rule, a "last Meal stays proposed" rule for end-of-day review, and a
    list of cases where the guess is wrong.
  - At 21:40, logging the day's meals folds them into one 21:40 Meal unless the user
    corrects every food.
  - A snack logged right after back-filling Lunch is proposed as part of Lunch.
- **Reason for Rejection**: Users think in meals, not foods. Every grouping rule this
  needs exists only to repair a guess that meal-first logging never makes.

### Alternative B: Drop Meal Types and show a timeline of foods

Remove Meal Types; the Nutrition Day becomes a list of timed foods.

- **Pros**: Fewer concepts; time is the only organiser.
- **Cons**:
  - People coming from slot-based trackers expect Breakfast, Lunch, Dinner and Snack.
  - The importers already map their data to Meal Types.
  - Custom types such as Pre-workout would be lost.
- **Reason for Rejection**: Meal Types carry meaning users and importers rely on. Making
  them cheaper (proposed from the clock, changed in two taps) removes their cost without
  losing that meaning.

### Alternative C: A time on every Food Entry

Each Food Entry gets its own eaten-at time, and a Meal's time span is derived from its
entries.

- **Pros**: More accurate for slow meals and grazing.
- **Cons**:
  - It changes the golden-vectored Food History and Last Portion orderings in Dart and
    TypeScript, which order by the Meal's start.
  - It turns the Meal's span into a derived value, which may not be stored.
  - Every food would need a time choice, which brings back the per-food decision this
    spec removes.
- **Reason for Rejection**: Its cost is out of proportion to the gain. A per-entry time can
  be added later without changing this model, as `LoggedSets.performedAt` was added to
  Workouts.

### Alternative D: A fixed default time on past days

Propose a time on a past day instead of requiring one, for example the Meal Type's usual
time, noon, or three hours after the previous Meal.

- **Pros**: One fewer step when back-filling.
- **Cons**: It stores a time that looks real and isn't. A user who saves without looking
  ends up with a made-up 08:00 breakfast in their fasting data, which is the problem this
  spec exists to fix.
- **Reason for Rejection**: Back-filling is rare enough that one time choice per Meal is
  cheap, and a wrong time costs more than a slower save.

### Alternative E: The Workout model for midnight

Keep a Meal's date fixed when its time is edited, so only the clock time changes.

- **Pros**: A Meal never moves between days unexpectedly; it matches Workouts.
- **Cons**:
  - A Meal moved from 23:50 to 00:10 would keep Monday's date with a Tuesday time.
  - The date and the instant would disagree, which is the same kind of mismatch as
    today's past-day bug.
- **Reason for Rejection**: For a timed eating event the time is the fact, and the date
  should follow it, as it does for Doses. The Dose model already exists in `_editDose`.

### Alternative F: Derive "time unknown" from the import source

Instead of a `time_precision` column, treat a Meal as untimed when its entries came from a
date-only importer.

- **Pros**: No schema change.
- **Cons**:
  - Not every file from an importer is date-only: Lifesum files are date-only only in the
    DD/MM layout.
  - A Meal the user later adds a food to, or retimes, would still read as untimed.
  - Agents can't say a time is unknown at all.
- **Reason for Rejection**: Precision is a property of the Meal, not of where its Food
  Entries came from. The column is set by importers and agents, and changes only when a
  time is chosen.

### Alternative G: Partial undo of a Meal's creation

When the Batch that created a Meal is undone after more Food Entries were added, undo the
Meal and re-home or archive the later entries, or undo only the first entry.

- **Pros**: Undo never says no.
- **Cons**:
  - Undo is all-or-nothing everywhere else, in the app and on the server.
  - A partial undo either touches rows outside the Batch, which no other undo does, or
    leaves a result the user didn't ask for.
- **Reason for Rejection**: Refusing with a `dependent` reason keeps undo's existing
  contract, and the user has Delete meal and entry removal for the same outcome.

### Alternative H: A separate agent operation for editing Meals

Add `updateAgentMeal` for Meal fields and keep `batchWriteAgentMeal` for entries.

- **Pros**: Each operation is simpler to describe.
- **Cons**:
  - Two ways to write the same Meal.
  - An agent that logs a coffee and corrects the time would need two calls, two
    idempotency keys and two Batches.
  - The existing operation's whole-row rewrite would still need fixing.
- **Reason for Rejection**: Making the existing operation write only sent Meal fields
  fixes the damage and covers editing with one operation, which matches the one
  repository write the app makes per action.

### Alternative I: Field-level conflict resolution in sync

Merge Meal changes per field, not per row, so an offline phone and an agent can each change
different fields of the same Meal without one losing.

- **Pros**: No lost edits from concurrent writers.
- **Cons**: It changes the sync protocol for every entity, or makes Meals a special case,
  and it touches the last-writer-wins invariant.
- **Reason for Rejection**: Out of proportion here. The losing version is already
  recoverable in the Activity Log. This spec removes the avoidable source of reverts: agent
  writes rewriting fields they didn't send.

### Alternative J: Show Dose and Workout times while logging

Mark the day's Doses and Workouts on the time sheet, or hint "40 minutes before your Dose".

- **Pros**: The user sees a timing conflict at the moment they log.
- **Cons**:
  - It adds reading and deciding to the logging path.
  - It would put locked Protocols data on an unlocked screen.
- **Reason for Rejection**: Logging screens show nutrition only. Comparing meals with Doses
  and Workouts belongs to review, where the analysis happens.

### Alternative K: Your meals as the most recent Meals

List the 3–5 most recent Meals with two or more foods instead of a frequency-ordered Meal
History.

- **Pros**: No new derived read, golden vector or agent operation.
- **Cons**:
  - The meal a user repeats most (the weekday breakfast) drops off the list after a
    weekend of different meals.
  - It doesn't match Your foods, which is ordered by frequency.
- **Reason for Rejection**: Ordering repeats by how often they happen is what makes a
  repeat one tap. The cost is one read built the same way as Food History.

### Alternative L: Two specs, time model first

Split this work into a Meal time model spec and a Meal logging flow spec.

- **Pros**: Each document is smaller to review.
- **Cons**:
  - The time model has no purpose apart from the logging screens, and the screens can't
    be built without it.
  - The feature's rules would be spread across two documents.
- **Reason for Rejection**: The project keeps one spec per feature. The implementation can
  still land in staged pull requests against this one spec, and the standalone fixes land
  in stage 1.

### Alternative M: Store the device's IANA zone name

Read the zone name (for example `Europe/Lisbon`) from the platform at startup and store it
in `meals.timezone`, as the contract field's old description suggested.

- **Pros**: The stored label matches the contract's description, and a future reader
  could re-derive offsets.
- **Cons**:
  - It adds a startup platform call, a provider and a constructor argument.
  - It stores a finer location signal than an abbreviation, and syncs it.
  - No reader uses it: the offset alone fixes the clock time and the date.
- **Reason for Rejection**: Nothing needs it. Doses and Workouts keep the abbreviation
  too.

### Alternative N: Backfill existing imported Meals as `date`

In the migration, mark an existing Meal `date` when it starts at local midnight, has at
least one active Food Entry, and every active entry carries an `import_source` of
`myfitnesspal`, `cronometer`, `yazio` or `lifesum`. The SQL predicate would be
`strftime('%H:%M:%S', started_at, 'unixepoch', 'localtime') = '00:00:00'`.

- **Pros**: Already-imported days show `time not recorded` too.
- **Cons**:
  - The migration's local midnight is the device's current zone, not the import's.
  - The migrated value stays on the device until the Meal next changes, because a
    migration writes no Activity Log image to sync.
  - No store release exists, so almost nobody has such Meals.
- **Reason for Rejection**: The complexity buys nothing for the people who will install
  the app. See §13, decision 6.

## Non-Functional Requirements

### Performance

- A food, a Log again, `Add foods later`, an entry removal, a Portion edit and every
  header change each confirm within one frame. Each is one local transaction; nothing on
  the Meal screen waits on the network or a platform call.
- The Meal screen opens without a spinner. Its first frame shows the header and search.
  Your foods is the existing reactive read; Your meals is one SQL query read once when the
  screen opens (§5), and its section appears when the query returns.

### Reliability

- Kill-and-reopen at any point leaves either the whole action or none of it: no Meal
  without its first Food Entry when the action was a food, and no half-copied Log again.
- The schema migration adds two columns. It never changes `started_at`, `local_date`,
  `timezone` or any Food Entry.
- Archive restore accepts backups made before v65 (§11, stage 2).

### Compatibility and rollout

- The server and the app can ship in either order (§10).
- An app from before this change keeps working against the new server: its pushes keep
  the new keys as stored, and its agent reads ignore the new fields.
- Rows written before this change (null offset) read through the device zone, the same as
  legacy Doses.

### Accessibility

- Every control on the Meal screen and the time sheet is at least 48 dp.
- The header is one button, with a semantic label that reads the time or `now`, the type,
  and that it can be changed, for example `now, Lunch. Change time or meal type`.
- `add foods` and `time not recorded` are text, never colour alone.
- The screen holds at 200% text scale without clipping the header or `Add foods later`.
- The Undo bar after Log again is announced to screen readers.
- WCAG AA contrast in both themes, using DESIGN.md tokens only.

### Privacy

- The Meal screen reads no Protocols or Workout data.
- No new location data is stored or synced: `timezone` keeps its current abbreviation,
  and the offset is coarser than it.
- No behavioural analytics are added.

### Localisation

- Every new string is an ARB message in `app_en.arb`. Times are formatted with the
  device's 12- or 24-hour preference.

## Detailed Implementation Plan

The work lands in three pull requests against this one spec, each targeting `main` and
each green on its own. The spec pull request (this document plus its SITEMAP entry) merges
first. The stages merge in order: stage 2 uses stage 1's `local_clock.dart` and Meal
validation, and stage 3 uses stage 2's repository.

### Stage 1: shared rules, golden vectors and the server

The stage puts both languages' cores in one pull request, so a golden vector never has
only one runner.

**Golden vectors** (`packages/golden-vectors/vectors/`):

| File | Change |
|---|---|
| `m39-meal-validation.json`, `m39-meal-validation.schema.json` | Create. Domain `meal-validation`, in the case shape of §8. Cases for each of the three rules, a future time at exactly 5 minutes and just over, and offsets at −720, 0 and +840 with times that cross midnight forwards and backwards. |
| `README.md` | Register the domain, modelled on the m37-training-progress entry. |

Meal History (m38) lands whole in stage 2, because its Dart runner reads the
`time_precision` column, and the Dart ownership guard fails any vector without a Dart
runner.

**Dart cores** (`apps/mobile/`):

| File | Change |
|---|---|
| `lib/domain/common/local_clock.dart` | Create. Move `clockAtOffset` here unchanged, and add `localDateAtOffset(DateTime instant, int? offsetMinutes) → ({int year, int month, int day})` (§1). |
| `lib/domain/protocols/protocols.dart` | Remove `clockAtOffset` and import it from `local_clock.dart`. |
| `lib/features/protocols/widgets/protocols_day_view.dart`, `lib/data/repositories/training_repositories.dart` | Import `clockAtOffset` from its new home. No behaviour change. |
| `lib/domain/nutrition/meal_validation.dart` | Create. `MealTimeInput`, `MealValidationResult` and `validateMealTime` with the three rules in §8, shaped like `dose_validation.dart`. |
| `test/domain/meal_validation_golden_test.dart` | Create. Run m39: the rules, and `localDateAtOffset` against `expected.localDate`. |
| `test/domain/local_clock_test.dart` | Create. `localDateAtOffset` with a null offset, and the frozen-offset rule across a DST change in the device zone (`startedAt.toLocal().timeZoneOffset` at a summer instant read in winter). |
| `test/domain/golden_vector_ownership_test.dart` | Add `meal-validation` to `_dartRunnerByDomain`. (`meal-history` is added in stage 2 with its runner.) |

**Server** (`apps/server/src/`):

| File | Change |
|---|---|
| `timezone.ts` | Add the pure `localDateAtOffset(instant, offsetMinutes)`. |
| `agent-validation.ts` | Add `validateAgentMealTime` with the three Meal rules, used by the batch write and the vector runner. |
| `index.ts` | Export `validateAgentMealTime`; wire the Meal Types route's Drizzle store, as for Food History. |
| `agent-meal-batch-write.ts` | Apply the §9 contract diff to the request, issue and response schemas. Add the pure `prepareAgentMealBatchWrite(request, stored, now)` implementing the field rules. Change `AgentMealBatchWriteStore.writeMealBatch` to select the stored Meal and entry payloads `FOR UPDATE` after the idempotency check, call it, and write the prepared rows or return the issues. |
| `agent-meal-types.ts` | Create. Route `GET /agent/meal-types` (`listAgentMealTypes`), its response schema and its own Drizzle read store. |
| `agent-nutrition-reads.ts` | Add `timezoneOffsetMinutes` and `timePrecision` to `AGENT_MEAL_LIST_FIELDS`, the default field set and `AgentMealListItemSchema`, reading `null` and `instant` for older payloads. |
| `agent-activity.ts` | Add the dependent check to the pre-check pass of `undoAgentActivityBatch`, and `skipped_dependent` to the outcome enum. |
| `sync.ts` | Add the Meal and Food Entry keys to `SYNC_CARRY_FORWARD_PAYLOAD_KEYS`, and re-implement `pushMealsInTransaction` and `pushFoodEntriesInTransaction` as adapters over `pushOpaqueSyncRowsInTransaction` (§10). |
| `app.ts` | Register the Meal Types route, and pass the batch-write store through the new pipeline. |
| `agent-mcp.ts` | Register `agent_list_meal_types`, and update the input schema of `agent_batch_write_meal` to the §9 shape, calling the same store. |

The server stores Meals as a JSON payload, so there is no Postgres migration.

**Contract and agent skill:**

| File | Change |
|---|---|
| `packages/contract/openapi.json`, `packages/contract/src/agent-client.ts`, `apps/mobile/lib/api/perennia_api_client.dart` | Regenerate with the contract job's scripts. Never edit by hand. |
| `packages/contract/src/agent-skill-reference.ts` | Edit by hand; this registry is not generated, and `generate` throws without it. Add `listAgentMealTypes: "list-meal-types"` to `AGENT_SKILL_COMMAND_NAMES` and `agent_list_meal_types` to `AGENT_MCP_TOOL_NAMES`. |
| `packages/contract/src/agent-validation.ts` | Export the Meal validation issue schema, as the dose schemas are exported. |
| `agent-skills/perennia/scripts/prn-agent.mjs`, `agent-skills/perennia/scripts/prn-code.mjs` | Add `list-meal-types` to the command maps. `prn-code.mjs` keys methods by operationId. |
| `agent-skills/perennia/references/api-operations.md` | Regenerate its marked operations block; edit the prose by hand to document the Meal Types read and the `log-meal` field rules: an absent field keeps its value, `null` clears it, and the time block's offset resolution. |
| `agent-skills/perennia/SKILL.md` | Document the same rules in the `log-meal` section. |

**Server tests** (`apps/server/test/`):

| File | Change |
|---|---|
| `agent-validation.golden.test.mjs` | Add a `meal-validation` branch that runs `validateAgentMealTime` and also asserts `localDateAtOffset(startedAt, offset) === expected.localDate`. |
| `timezone.test.mjs` | Add `localDateAtOffset` cases, and `offsetMinutesInTimezone` across a DST change. |
| `agent-meal-batch-write.test.mjs` | Add: create with only an IANA zone; create with only an abbreviation and a `localDate` stores a null offset and that date; the same without `localDate` is 422 `meal_offset_unknown`; create without `mealType` is 422 `meal_create_incomplete`; a zero-entry create; update with only `startedAt` moving the derived `localDate` across midnight; an entries-only request leaves the Meal row and its `updatedAt` untouched; an entries-only request for an unknown id is 404; an unsent entry `deletedAt` and the import keys keep their stored values; `null` clears `endedAt`; entries into an archived Meal are 422 `meal_archived`, and accepted when the same request sends `deletedAt: null`; another user's Meal id and entry id are 409; an entry id under a different Meal is 422 `entry_meal_mismatch`; a future `startedAt` returns a top-level warning. |
| `agent-meal-types.test.mjs` | Create. Route auth; archived types excluded; order by `sortOrder` then `id`. |
| `agent-meal-reads.test.mjs` | Add the two new fields on `listAgentMeals`, including `null` and `instant` for an older payload. |
| `agent-activity.test.mjs` | Add: undoing a Meal's creating Batch after another Batch added an entry returns `skipped_dependent` and applies nothing. |
| `agent-mcp.test.mjs` | Add `agent_list_meal_types` and an `agent_batch_write_meal` call with Meal fields only. |
| `sync-convergence.test.mjs` | Extend: a push from an app without this change keeps the stored Meal keys and Food Entry import keys; a push that sends them replaces them; per-row last-writer-wins unchanged. |

**CI:** `tools/ci-local.mjs` and `.github/workflows/ci.yml`, in the same commit: add
`apps/server/src/timezone.ts` and `apps/server/test/timezone.test.mjs` to the `golden`
job's path filters.

**Docs:** `CONTEXT.md` gets the Meal, Time Precision and Meal Type terms from §12.
`CHANGELOG.md`, under `## [Unreleased]`:

- Added: "Agents can list Meal Types (`listAgentMealTypes`)."
- Added: "`listAgentMeals` returns each Meal's `timezoneOffsetMinutes` and
  `timePrecision`."
- Changed: "`batchWriteAgentMeal` writes only the Meal fields a request sends; `localDate`
  is derived when the offset is known."
- Fixed: "An agent write no longer un-archives a Meal, drops Food Entry import keys, or
  moves an entry to another Meal."
- Fixed: "An agent undo is refused when other writes added foods to the Meal it created."

### Stage 2: the app's data layer

After this stage the data is right and the old screens still work: `startMeal` keeps
working, with the past-day fix, until stage 3 removes it. Meal History lands here in both
languages, with its agent read.

| File | Change |
|---|---|
| `apps/mobile/lib/domain/nutrition/meal_type_proposal.dart` | Create. `proposeMealType` from §4; the repository uses it to resolve a null `mealTypeName`. |
| `apps/mobile/lib/data/local/app_database.dart` | Add the two columns to `meals`; set `schemaVersion` to 65; add a guarded migration step that adds them and changes no values. |
| `apps/mobile/lib/data/local/app_database.g.dart` | Regenerate. |
| `apps/mobile/drift_schemas/app_database/drift_schema_v65.json` | Create with `drift_dev schema dump`. |
| `apps/mobile/test/generated_migrations/app_database/schema_v65.dart`, `schema.dart` | Regenerate with `tool/drift_schema_snapshots.dart`. |
| `apps/mobile/lib/domain/nutrition/nutrition.dart` | Add the `MealTimePrecision` enum, `MealTarget`, `ExistingMealTarget`, `NewMealTarget`, `PendingMeal`, `MealAlreadyExistsException`, `LogMealAgainResult` and `MealHistoryRecord`. Change `MealDraft`: remove `localDate`, add `timezoneOffsetMinutes` and `timePrecision`. Add the offset, the precision and `clock` (the local time at its offset) to `MealRecord`. |
| `apps/mobile/lib/data/repositories/training_repositories.dart` | **NutritionRepository:** implement the §3 table and rules; `_createMeal` computes the frozen offset, uses `localDateAtOffset`, stores the precision, and calls `validateMealTime` in place of its ad-hoc checks; `listMealHistory` (§5), extracting `foodHistoryWindow` from `listFoodHistory`; `startMeal` builds `startedAt` from the selected day (§3); the §7 re-import changes in `importNutritionBatch`, `_findOrCreateImportMeal` and `_updateImportedFoodEntry`. **Activity Log:** `_mealImage` writes the two keys; `_mealCompanionFromImage` reads them and re-derives a malformed `local_date` (§10); add the Meal entry to `_activityLaterAddedKeyDefaults`; `undoBatch` calls `_mealDependentUndoConflicts`; add `ActivityLogUndoConflictReason.dependent`. |
| `apps/mobile/lib/data/repositories/portable_archive_repository.dart` | Decode Meals with `MealRow.fromJson({'timePrecision': 'instant', ...json})`, as exercises default `focusIds`, so backups made before v65 still restore. |
| `apps/mobile/lib/domain/nutrition/nutrition_import.dart` | Add the named parameter `timePrecision` to `NutritionImportMeal`, defaulting to `instant`. |
| `apps/mobile/lib/features/nutrition/import/myfitnesspal_csv_import_adapter.dart`, `cronometer_csv_import_adapter.dart`, `yazio_import_adapter.dart`, `lifesum_import_adapter.dart` | Set the precision by the rule in §1. |
| `apps/mobile/lib/features/nutrition/controllers/add_food_controller.dart`, `nutrition_day_controller.dart`, and the importers' `MealDraft` call sites | Stop passing `localDate:` to `MealDraft`; replace `logQuickEntryForMeal` calls with `logQuickEntry(target: ExistingMealTarget(...))`; pass `ExistingMealTarget` to `logFoodEntrySnapshot`. |
| `apps/mobile/lib/features/activity/undo_conflict_message.dart` | Create. Move `_undoConflictMessage` here from `activity_feed_screen.dart` as a public function, and add the `dependent` branch (§7). |
| `apps/mobile/lib/features/activity/widgets/activity_feed_screen.dart` | Call the shared function. |
| `apps/mobile/lib/l10n/app_en.arb` and generated localisations | Add the `dependent` message. |

**Meal History, both languages:**

| File | Change |
|---|---|
| `packages/golden-vectors/vectors/m38-meal-history.json`, `m38-meal-history.schema.json` | Create, in the m37 format with `schema` and `schemaVersion`. Domain `meal-history`. Cases: qualifying and non-qualifying Meals (one Food, two entries of the same Food, a Quick Entry alongside two Foods, `date` precision, archived Meal, archived User Food, exactly 90 days old, 91 days old), the same Foods with different Portions as one identity, the canonical string's ordinal order, ties on count broken by recency then the canonical string, the `limit` cap, and names taken from the most recent Meal. |
| `packages/golden-vectors/vectors/README.md` | Register the domain, modelled on the m37-training-progress entry. |
| `apps/server/src/meal-history.ts` | Create. Export `buildMealHistory(rows, {now, limit})` (§5). |
| `apps/server/src/agent-meal-history.ts` | Create. Route `GET /agent/meals/history` (`listAgentMealHistory`), its query and response schemas, and `createDrizzleAgentMealHistoryReadStore`, mirroring `agent-food-history.ts`. |
| `apps/server/src/app.ts`, `index.ts` | Register the route and wire its Drizzle store, as for Food History. |
| `apps/server/src/agent-mcp.ts` | Register `agent_list_meal_history`. |
| `apps/server/package.json` | Add `test/meal-history.golden.test.mjs` to `test:golden-vectors`. |
| `packages/contract/openapi.json`, `packages/contract/src/agent-client.ts`, `apps/mobile/lib/api/perennia_api_client.dart` | Regenerate with the contract job's scripts. |
| `packages/contract/src/agent-skill-reference.ts` | Add `listAgentMealHistory: "list-meal-history"` to `AGENT_SKILL_COMMAND_NAMES` and `agent_list_meal_history` to `AGENT_MCP_TOOL_NAMES`. |
| `agent-skills/perennia/scripts/prn-agent.mjs`, `prn-code.mjs`, `references/api-operations.md`, `SKILL.md` | Add `list-meal-history` to the command maps, regenerate the operations block, and document the read. |
| `tools/ci-local.mjs`, `.github/workflows/ci.yml` | In the same commit, add `apps/server/src/meal-history.ts` and `apps/server/test/meal-history.golden.test.mjs` to the `golden` job's path filters. |
| `apps/server/test/meal-history.golden.test.mjs` | Create. Run m38 against `buildMealHistory`. |
| `apps/server/test/agent-validation.golden.test.mjs` | Add `"meal-history"` to `DOMAINS_OWNED_ELSEWHERE`. |
| `apps/server/test/agent-meal-history.test.mjs` | Create. Route auth, `limit` default and maximum, the response shape, and parity with `buildMealHistory` over seeded rows. |
| `apps/server/test/agent-mcp.test.mjs` | Add `agent_list_meal_history`. |

**App tests:**

| File | Change |
|---|---|
| `test/domain/nutrition/meal_type_proposal_test.dart` | Create. Each window edge (04:00, 10:29, 10:30, 14:59, 15:00, 16:59, 17:00, 21:59, 22:00, 03:59); a renamed seeded type proposed under its new name; archived seeds falling back to Snack, then to the first active type, then to the label `Snack`. |
| `test/features/nutrition/nutrition_repository_test.dart` | Against in-memory SQLite: `logFoodEntrySnapshot` and `logQuickEntry` with a `NewMealTarget` create both rows in one Batch, resolve a null `startedAt` to the write time and a null type to the proposal, and throw `MealAlreadyExistsException` on an existing id; an entry draft with a different `mealId` throws; `createMeal` stores the pending id, the frozen offset and the precision; `logMealAgain` into a new and an existing Meal, re-reading an active User Food, copying snapshots of a USDA Food, an archived User Food and a disallowed Portion, copying Quick Entries, and dropping import keys; `updateMealTime` moving `local_date` across midnight with the offset kept, freezing a legacy null offset at the new instant, and turning `date` into `instant`; `updateMealType`; `listMealHistory` order, cap and window; the `dependent` undo refusal, and a normal undo of a lone first food; removing the last entry keeps the Meal; `startMeal` on a past day stores that day. |
| `test/domain/meal_history_golden_test.dart` | Create. Run m38 through `listMealHistory` against in-memory SQLite, as `food_history_golden_test.dart` runs m37. |
| `test/domain/golden_vector_ownership_test.dart` | Add `meal-history` to `_dartRunnerByDomain`. |
| `test/data/schema_snapshot_migration_test.dart` | Add a v64 → v65 case: the columns are added, existing Meals read `instant` with a null offset, and no other value changes. |
| `test/data/portable_archive_repository_test.dart` | Add: restoring a v64-shaped archive containing a Meal succeeds and reads `instant`. |
| `test/data/meal_logging_reopen_test.dart` | Create. With `kill_point_snapshot_interceptor.dart`, kill during a `NewMealTarget` `logFoodEntrySnapshot` and during `logMealAgain`, reopen, and find all of the action or none of it. |
| `test/features/nutrition/nutrition_import_repository_test.dart` | Add: re-import leaves an edited entry in its Meal and creates no empty Meal; an import never reuses a Meal with a user-added food or a Meal with no entries; precision stored from the adapter. |
| `test/features/nutrition/myfitnesspal_csv_import_adapter_test.dart`, `cronometer_csv_import_adapter_test.dart`, `yazio_import_adapter_test.dart`, `lifesum_import_adapter_test.dart` | Add the precision each adapter sets, with and without a time. |
| `test/features/sync/sync_repository_test.dart` | Add: pull applies an older image without the two keys and leaves the columns as stored; push images carry both keys; a malformed `local_date` is re-derived; undo of a pre-upgrade Meal Batch is not stale. |
| Every test that passes `localDate:` to `MealDraft` or calls `logQuickEntryForMeal` | Update to the new signatures. |

`CHANGELOG.md`, under `## [Unreleased]`:

- Fixed: "A Meal started on a past day is saved on that day, not today."
- Fixed: "Re-importing a file no longer moves a food out of a meal you edited."
- Fixed: "Backups keep restoring after the update."
- Added: "Agents can read the user's repeated meals (`listAgentMealHistory`)."

`CONTEXT.md` gets the Meal History term from §12.

### Stage 3: the Meal screen

After this stage the user logs Meals through the Meal screen, the Start Meal chips are
gone, and the Nutrition Day reads in time order.

| File | Change |
|---|---|
| `apps/mobile/lib/features/nutrition/controllers/meal_screen_controller.dart` | Create. `MealScreenArgs` and the `MealScreenController` family (§6): the pending Meal, the saved Meal stream once written, the Meal History future, the recent-Meal shortcut, and the in-flight guard; it exposes the §6 states and calls the repository. |
| `apps/mobile/lib/features/nutrition/widgets/meal_screen.dart` | Create. The full-screen route with the states and behaviour of §6. |
| `apps/mobile/lib/features/nutrition/widgets/meal_time_sheet.dart` | Create. The date and time pickers, the time-shift buttons, the Meal Type list and the future-time confirmation (§6). |
| `apps/mobile/lib/features/nutrition/widgets/add_food_picker.dart`, `controllers/add_food_controller.dart` | Replace the required `MealRecord` with a `MealTarget`; render embedded in the Meal screen; route Quick Entry through `logQuickEntry(target: ...)`. Search, source chips, Your foods and the two-tap repeat are unchanged. |
| `apps/mobile/lib/features/nutrition/widgets/log_portion_screen.dart` | Take a `MealTarget`; Save calls `logFoodEntrySnapshot` and pops with the saved Meal id. Add the prefilled edit mode whose Save calls `updateFoodEntryPortion`. |
| `apps/mobile/lib/features/nutrition/widgets/quick_entry_dialog.dart` | Return the entered values only; the write happens in the picker. |
| `apps/mobile/lib/features/nutrition/widgets/nutrition_day_view.dart` | Replace the Start Meal chips with `Log meal`, hidden on future days; rename `startMealButtonKey` to `logMealButtonKey`; cards lead with `<time> · <type>` (or `time not recorded`), then Food Entries and totals; `add foods` on zero-entry Meals; a card tap opens the Meal screen; remove the per-card `Add food` button and `_showAddFoodPicker`. |
| `apps/mobile/lib/features/nutrition/controllers/nutrition_day_controller.dart` | Remove `startMeal` and `logQuickEntryForMeal`. |
| `apps/mobile/lib/domain/nutrition/nutrition_day_assembly.dart` | Apply the §6 order. |
| `apps/mobile/lib/features/home/widgets/home_screen.dart` | The Log sheet's Food item becomes Meal (`homeLogMeal`), opens the Meal screen for the selected day, and is hidden on a future day; rename `logFoodKey` to `logMealKey`; Today's Nutrition view replaces `onStartMeal` with the `Log meal` button. |
| `apps/mobile/lib/l10n/app_en.arb` and generated localisations | Add `homeLogMeal`, `nutritionLogMeal`, the header forms (`now`, `Choose time`, `add foods`, `time not recorded`), the header's semantic label, the time-shift buttons, `Add foods later`, `Your meals`, `Add to {time} · {type}`, `Meal logged` and `Undo`, Delete meal and its confirmation, and the future-time confirmation. Remove `homeLogFood`. Remove the literal Start Meal strings from the widgets. |

**Tests:**

| File | Change |
|---|---|
| `test/features/nutrition/meal_screen_controller_test.dart` | Create. The proposal follows the header until the first write, then is fixed; `now` resolves at the write; the shortcut's eligibility (0 and 30 minutes inclusive, 31 minutes, a `date` Meal, a future start, a zero-entry Meal); nothing is written when the screen closes early; a double tap writes one Meal; after undoing the first action the state is new with a fresh id. |
| `test/features/nutrition/meal_screen_test.dart` | Create. Each state in the §6 table and the `date` modifier; a past day opens the time sheet and disables picking until a time is chosen; time-shift buttons replace rather than stack and are absent on a past day; a Your meals row logs the Meal with Undo; remove and Portion edit on a Food-backed entry, remove-only on imported and Quick Entries; removing the last entry shows `add foods`; Delete meal is in the overflow menu and confirms; a refused undo shows the `dependent` message. Accessibility: `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` in light and dark, and the header and `Add foods later` unclipped at text scale 2.0. |
| `test/features/nutrition/nutrition_day_view_test.dart`, `test/domain/nutrition/nutrition_day_assembly_test.dart` | The new order, card header, `add foods`, `Log meal` hidden on future days, a card tap opening the Meal screen. |
| `test/features/nutrition/add_food_picker_test.dart`, `add_food_picker_state_test.dart`, `log_portion_screen_test.dart`, `quick_entry_dialog_test.dart` | Both target kinds; the repeat-food path is still the row, then Save; the Portion edit mode. |
| `test/app_shell_test.dart` | Update the Log sheet cases: the Meal item opens the Meal screen for the selected day and is hidden on a future day; the `Log meal` button on Today's Nutrition view; use `logMealKey` and `logMealButtonKey`. |

**Docs in this stage:**

- `docs/designs/unified-food-search.md`, `open-food-facts.md` and `food-aisles.md`: add a
  header note that the picker now takes a Meal target and is embedded in the Meal screen
  (amended by this spec).
- `DESIGN.md`: rename the Log action's Food item to Meal. `AGENTS.md`: in the screen map,
  the Log action offers Workout, Meal and Dose.
- This spec's Status becomes Current, and its SITEMAP row is updated.
- `CHANGELOG.md`, under `## [Unreleased]`:
  - Added: "Log a meal from one screen: repeat a whole meal from Your meals, add foods, or
    save just the time and add foods later."
  - Changed: "A meal's time is shown and can be changed, and its meal type is proposed
    from the time."
  - Changed: "The Nutrition Day lists meals in time order."

## Verification Plan

**The gate.** Stage 1 runs the full `pnpm ci:local`, because it touches every layer.
Stages 2 and 3 run `pnpm ci:local --changed`.

| Job | Stage | Covers |
|---|---|---|
| `golden` | 1, 2 | m38 and m39 in Dart and TypeScript; the ownership guards. |
| `contract` | 1, 2 | The regenerated OpenAPI document and clients match the routes; the skill registry lists the new operations. |
| `js` | 1, 2 | Server unit and route tests, including the batch-write, reads, undo and MCP tests above. |
| `sync` | 1 | `sync-convergence.test.mjs`, including the Meal and Food Entry carry-forward. |
| `mobile` | 1, 2, 3 | Analyze, format, Drift schema snapshot check, and the app tests above. |

**Standing scenarios:**

- Repositories against in-memory SQLite for every write in §3.
- Kill-and-reopen during a first food and during Log again.
- Sync simulation in both directions with an older app's images and payloads.
- Archive restore of a pre-v65 backup.

**Manual check on the reference Pixel 6a, after stage 3, on a release build installed
over the existing install:**

1. Log a repeat meal from Your meals today. Pass: the card shows the time of the tap, and
   Undo removes the Meal and its Food Entries in one step.
2. At "end of day", log three meals with their real times through the time sheet. Pass:
   the Nutrition Day lists them in time order with the chosen times.
3. Back-fill yesterday. Pass: the time sheet opens first, and the Meal appears on
   yesterday's Nutrition Day.
4. Move a Meal from 23:50 to 00:10 the next day. Pass: it appears on the next day.
5. Ask an agent to add a coffee to that Meal. Pass: after sync the Meal keeps its
   corrected time.
6. TalkBack pass on the Meal screen and the time sheet. Pass: the header announces
   `now, Lunch. Change time or meal type`, each time-shift button announces its amount,
   and the Undo bar after Log again announces `Meal logged` with an `Undo` action.
