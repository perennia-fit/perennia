# Unified Food Search

*   **Author:** Leonardo Pinheiro
*   **Status:** Approved
*   **Date:** 2026-10-31

--------------------------------------------------------------------------------

## Overview

The add-food picker is where a user finds a **Food** to log into a **Meal**. It
opens from the Nutrition Day view, lists Foods, and opens the log-portion screen
for the one the user taps; saving there writes a **Food Entry**. These terms,
and **Food Source**, **Platform Food**, **User Food**, **Recipe** and
**Portion**, are defined in [CONTEXT.md](../../CONTEXT.md). How the app is
layered (widgets, controllers, repositories, Drift) is in
[ARCHITECTURE.md](../../ARCHITECTURE.md). The rules every spec must keep are in
[AGENTS.md](../../AGENTS.md), and the UI tokens are in
[DESIGN.md](../../DESIGN.md).

Today the picker asks the user to choose a Food Source before it shows any
Foods. It has four filter chips (Recent, Your Food, USDA, Open Food Facts) and
each search runs against the selected one only. This spec replaces that with
**one search over every source on the device**. The results are one ranked
list. The Foods the user has logged before come first, and each row says where
its data comes from. The chips stay, as an optional way to narrow the list.

Before the user types, the picker shows the user's own Foods, the ones they log
most often first, each with the Portion they used last time. Logging a repeat
Food then takes two taps after the picker opens: the row, then **Save** on the
log-portion screen.

This is phase 1 of two. Phase 2, browsing Open Food Facts products by **Aisle**,
is specified in [Food Aisles](food-aisles.md) and builds on this spec's picker.

This spec amends the picker section of
[Open Food Facts Integration](open-food-facts.md) (its section "The picker, the
scanner and the log-portion screen"). Everything else in that spec stands: the
bundle, the search and barcode rules, live requests, the request budget, the
online-lookups setting, attribution on the log-portion screen and the existing
agent operations.

Terms used below:

*   **Food History (new)**: the distinct Foods the user has logged, derived
    from Food Entries and used to order the picker. It is defined under
    [Vocabulary](#vocabulary).
*   **Last Portion**: the Portion of the user's latest Food Entry for a Food
    that has one. "Latest" is by the Meal's `startedAt`, then the entry's
    `updatedAt`, then the entry's `id`. This spec uses this one definition
    everywhere.
*   **Your foods**: the UI name for the Foods in Food History together with
    the user's active User Foods (including Recipes) that have never been
    logged.
*   **Catalogue** (a term local to this spec, not added to CONTEXT.md): the
    Platform Foods on the device, which are the USDA seed, the Open Food Facts
    bundle and the Open Food Facts device cache.
*   **Blank query**: a query for which `buildFoodSearchMatch(query)` returns
    `null` and `barcodeCandidates(query)` is empty. Both functions are defined
    in [Open Food Facts Integration § Search and barcode rules](open-food-facts.md#search-and-barcode-rules)
    and live in `apps/mobile/lib/domain/nutrition/open_food_facts.dart`. An
    empty query, a query of spaces and a query of punctuation only (`"!!!"`)
    are all blank. Every other query is a **typed query**.

## The Problem

A user on the Nutrition Day view taps **Add Food** and sees:

1.  The **Recent** chip selected, with an empty list for a new user ("No foods
    found").
2.  On **USDA**, three Foods. The USDA seed in
    `apps/mobile/assets/seeds/usda_foods.json` holds three Foods today.
3.  On **Open Food Facts**, before typing, the compact attribution notice (a
    sentence, a source link and an ODbL link) and the line "Type a product or
    brand name." There are no Foods.

The 41,737 bundled products are only reachable by choosing the right chip first
and then typing. A user who wants Greek yoghurt has to know which database
holds it before they can search, and an empty list reads as "this app has no
food list".

Recent is the default chip, but it lists Food Entries by when each was last
edited, so a one-off snack logged today sits above the oat milk logged every
morning. Recent also lists the logged snapshot, so a User Food the user has
since edited is offered with its old values.

The source-first model also makes the licence notice the most prominent thing
on the Open Food Facts chip. Attribution is required (ODbL, the Open Database
License; see
[Open Food Facts Integration § The licence, in short](open-food-facts.md#the-licence-in-short)),
but it does not need to replace the content.

## Goals

1.  **One search.** Typing searches Your foods and the whole Catalogue at once.
    The default filter is **All**, and no chip has to be chosen to find a Food.
2.  **Repeat in two taps.** Before typing, the picker lists Your foods, most
    often logged in the last 90 days first. Tapping one opens the log-portion
    screen prefilled with its Last Portion, and **Save** logs it.
3.  **Current Foods, not old snapshots.** A Your foods row shows the Food as it
    is now: an edited User Food or Recipe shows its new name and values, and an
    Open Food Facts product shows its current device copy.
4.  **Source on every row.** Each row shows its Food Source badge. Open Food
    Facts rows keep the ODbL marker, and one attribution notice follows the list
    whenever an Open Food Facts row is in it.
5.  **No network use while typing.** Nothing is sent as the user types. A live
    Open Food Facts request is sent only when the user taps the online row or
    uses the keyboard's search action, and only while the "Look up foods
    online" setting is on. This is today's Open Food Facts behaviour; it now
    also applies in the All filter (see [Submitting the query](#submitting-the-query)).
6.  **Within the existing budget.** A typed search's results appear within
    100 ms after the 300 ms typing pause ends, on the reference device of
    [Open Food Facts Integration § Performance and storage](open-food-facts.md#performance-and-storage).
7.  **The same read for agents.** Food History is a new read of the user's
    data, so agents get it as an operation too (see
    [Agent surface](#agent-surface)).

## Non-Goals

*   **Browsing by Aisle.** That is phase 2, [Food Aisles](food-aisles.md).
*   **Changing the search rules.** Your foods and USDA keep their substring
    match (`foodNameMatchesQuery`). Open Food Facts keeps its FTS5 word-prefix
    match and `bm25` (SQLite's full-text relevance score) order. This spec only
    decides how the results are combined.
*   **Changing the log-portion screen, Quick add, the barcode scanner or the
    barcode not-found state.**
*   **A larger USDA seed.** Growing the seed is its own change.
*   **Suggestions or judgements.** Ranking uses only the user's own logging
    and the source's text match and scan count. Nothing is ranked by nutrient
    values, and no Food is called healthy or recommended.
*   **A unified agent search.** Agents get Food History as its own read and
    keep composing the existing searches (see
    [Alternative E](#alternative-e-a-unified-agent-search-operation)).

## Open Questions

None. Decisions made while drafting and in review are recorded in
[Alternatives Considered](#alternatives-considered).

## Critical User Journeys (CUJs)

### CUJ 1: Log the usual breakfast

*   **Given** the user logged the Open Food Facts product "Oat milk" (brand
    Oatly) with a 250 ml Portion on most mornings in the last month, and the
    product is on the device.
*   **When** they tap **Add Food** on Breakfast.
*   **Then** the first row under "Your foods" is "Oat milk", with "Oatly", the
    Open Food Facts badge, its kcal per 100 ml and "Last: 250 ml". They tap it.
    The log-portion screen opens with 250 ml, and they tap **Save**: two taps
    after the picker opens.

### CUJ 2: A new user searches for a packaged product

*   **Given** a new install with no Food Entries and the bundle installed.
*   **When** they open the picker.
*   **Then** they see the search field, the chips with **All** selected, and
    the line "Search by name or brand, or scan a barcode." There is no empty
    "Recent" heading and no licence block.
*   **When** they type "chobani gr" and pause.
*   **Then** within 100 ms after the pause the list shows the bundle's matching
    products. Each row shows its brand, the "Open Food Facts · ODbL" badge and
    kcal per 100. Below them is the row `Search Open Food Facts online for
    "chobani gr"`, then the compact attribution notice.

### CUJ 3: A generic food and a logged food share a name

*   **Given** the user has logged "Milk, whole" (USDA) once and has a User Food
    "Milk – office fridge" they have never logged.
*   **When** they type "milk".
*   **Then** the list starts with the logged "Milk, whole", then "Milk – office
    fridge", then the remaining USDA matches, then Open Food Facts milks.
    "Milk, whole" appears once, as the Your foods row, with its Last Portion.

### CUJ 4: Find a product that is not on the device

*   **Given** online lookups are on and the device is online.
*   **When** the user types "kalbi chips", finds no match, and taps the online
    search row.
*   **Then** the device's matches stay on screen. The row shows progress, then
    a "From Open Food Facts" group lists the live results below it, as in
    [Open Food Facts Integration CUJ 4](open-food-facts.md#cuj-4-find-a-product-that-is-not-on-the-device-by-name).

### CUJ 5: Narrow to one source

*   **Given** the picker is open on All with "yog" typed, and the device has
    Open Food Facts yoghurts.
*   **When** the user taps the **Open Food Facts** chip.
*   **Then** only Open Food Facts rows are shown, from the device and from any
    live search, and the online row stays.
*   **When** they clear the query.
*   **Then** the list shows the line "Search Open Food Facts by product name,
    brand or barcode." and nothing else.

### CUJ 6: The app is killed after logging

*   **Given** the user logged "Banana" from the picker.
*   **When** the app is killed and reopened, and they open the picker again.
*   **Then** "Banana" is in Your foods with that Portion as its Last Portion.

### CUJ 7: An edited User Food

*   **Given** the user logged the User Food "Protein oats" every day, then
    renamed it "Overnight oats" and changed its protein value.
*   **When** they open the picker, and when they type "overnight".
*   **Then** both lists show one row named "Overnight oats" with the new
    values and the Last Portion. Typing "protein oats" does not find it.

### CUJ 8: An agent logs the user's usual Food

*   **Given** an agent with an API key is asked to "log my usual breakfast".
*   **When** it calls `listAgentFoodHistory`.
*   **Then** it receives the user's Foods in the picker's order, each with its
    Food Source, Food id, recent count, last-logged time and Last Portion, and
    can log one through the existing Meal batch write.

## Technical Plan (Architecture)

### Overview of the parts

| Layer | Part | Change |
| :---- | :--- | :----- |
| Widget | `AddFoodPicker` (`add_food_picker.dart`) | New layout: the All default, the Your foods view, one list, attribution as a footer |
| Controller | `AddFoodPickerController` (`add_food_controller.dart`) | `autoDispose`; default filter All; loads Your foods once per opening; submitting in All behaves as Open Food Facts does today |
| Repository | `AddFoodRepository` (`add_food_repository.dart`) | New `loadYourFoods`; `search` gains the All and Your foods filters and the merge rules below |
| Repository | `NutritionRepository` (`training_repositories.dart`) | New `listFoodHistory`, replacing `listRecentFoodEntries`; `lastPortionForFood` and `lastPortionsForFoods` are removed |
| Repository | `OpenFoodFactsRepository` (`open_food_facts_repository.dart`) | New `localProductsByCodes` |
| Domain | `nutrition.dart` | New `FoodHistoryRecord` |
| Server | `agent-food-history.ts`, `food-history.ts` (new) | `listAgentFoodHistory` REST operation and its store |
| Server | `agent-mcp.ts` | `agent_list_food_history` MCP tool |
| Contract | `packages/contract` | Generated from the new route |
| Golden vectors | `packages/golden-vectors/vectors/m37-food-history.json` (new) | Food History order and Last Portion, run in Dart and TypeScript |

There are no Drift schema changes, no new tables, no new index, and no sync
changes.

### Filters

`AddFoodPickerFilter` becomes:

| Value | Chip label | Searches |
| :---- | :--------- | :------- |
| `all` (default) | All | Your foods and the Catalogue |
| `yours` | Your foods | Your foods only |
| `usda` | USDA | The USDA seed |
| `openFoodFacts` | Open Food Facts | The bundle and device cache, plus live search |

The `recent` and `user` values are removed. The chips are shown in the order
above. Each opening of the picker starts with filter `all` and an empty query
(see [Controller lifecycle](#controller-lifecycle)).

### Food History

Food History is an **ordering signal**. It says which Foods the user logged,
how often and when, and their Last Portion. It does not supply a Food's facts:
those come from the current Food (see [Your foods](#your-foods)).

`NutritionRepository.listFoodHistory({DateTime? now})` returns
`List<FoodHistoryRecord>` in Food History order. It is computed on each call
and never stored.

**Which entries count.** These are Food Entries with `deletedAt` null,
`entryKind` = `food`, `foodId` and `foodSource` not null, and `isLiquid` not
null, whose Meal has `deletedAt` null. Entries for an archived User Food
(`foodSource` = `user` and the Foods row's `deletedAt` not null) are left out.
Archiving is the user-facing delete for User Foods, so the picker must not
offer an archived Food. The exclusion has to happen in this read: the picker
logs through `logFoodEntrySnapshot`, which does not check archive state, so an
archived Food left in the list would log without complaint. The archived
Food's Food Entries and their history are kept. Imported Food Entries have a
null `foodId` (see CONTEXT.md, Food Entry), so they never count.

**One record per Food.** Entries are grouped by (`foodSource`, `foodId`). For
each group:

*   **`recentCount`** is the number of the group's entries whose Meal
    `startedAt` is at or after `now − Duration(days: 90)`, an instant 90 × 24
    hours before `now`. `now` defaults to `DateTime.now()`, as the
    repository's other date-relative reads do.
*   **`lastLoggedAt`** is the greatest Meal `startedAt` in the group.
*   **`latestEntryId`** is the `id` of the group's latest entry (greatest Meal
    `startedAt`, then entry `updatedAt`, then entry `id`).
*   **`latestPosition`** is that entry's `position` within its Meal.
*   **`lastPortion`** is the group's Last Portion, or `null` if no entry in the
    group has a Portion.

**Order.** `recentCount` descending, then `lastLoggedAt` descending, then
`latestPosition` ascending, then `foodSource` name ascending, then `foodId`
ascending. A Food not logged in 90 days has a `recentCount` of 0, so it falls
below the frequent ones but stays in the list, ordered by recency. Foods logged
in the same Meal share a `lastLoggedAt`, so `latestPosition` keeps them in the
order the user logged them. The order uses nothing but the Food Entries and
Meals, so the app and the server compute the same order, and golden vectors
check it (see [Validation and analytics](#validation-and-analytics)).

**Shape.**

```dart
final class FoodHistoryRecord {
  final FoodSource foodSource;
  final String foodId;
  final int recentCount;
  final DateTime lastLoggedAt;
  final int latestPosition;
  final String latestEntryId;
  final Portion? lastPortion;
}
```

**Query.** One `customSelect`. Its shape, in SQL with named parameters:

```sql
WITH active AS (
  SELECT e.food_source, e.food_id, m.started_at, e.updated_at, e.id,
         e.position, e.portion_json
  FROM food_entries e
  JOIN meals m ON m.id = e.meal_id
  LEFT JOIN foods f ON e.food_source = 'user' AND f.id = e.food_id
  WHERE e.deleted_at IS NULL AND m.deleted_at IS NULL
    AND e.entry_kind = 'food' AND e.food_id IS NOT NULL
    AND e.food_source IS NOT NULL AND e.is_liquid IS NOT NULL
    AND f.deleted_at IS NULL
), ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY food_source, food_id
      ORDER BY started_at DESC, updated_at DESC, id DESC) AS latest_rank,
    ROW_NUMBER() OVER (PARTITION BY food_source, food_id
      ORDER BY portion_json IS NULL, started_at DESC, updated_at DESC, id DESC)
      AS portion_rank
  FROM active
)
SELECT food_source, food_id,
  SUM(CASE WHEN started_at >= :cutoff THEN 1 ELSE 0 END) AS recent_count,
  MAX(started_at) AS last_logged_at,
  MAX(CASE WHEN latest_rank = 1 THEN id END) AS latest_entry_id,
  MAX(CASE WHEN latest_rank = 1 THEN position END) AS latest_position,
  MAX(CASE WHEN portion_rank = 1 THEN portion_json END) AS last_portion_json
FROM ranked
GROUP BY food_source, food_id
ORDER BY recent_count DESC, last_logged_at DESC, latest_position ASC,
  food_source ASC, food_id ASC
```

`:cutoff` is `now − Duration(days: 90)`, bound the way Drift stores the
`started_at` column. A User Food entry whose Foods row is missing (for example
a synced entry that arrived before its Food) has no joined row, so
`f.deleted_at` is null and the entry counts. The query declares `readsFrom`
`foodEntries`, `meals` and `foods`.

### Your foods

`AddFoodRepository.loadYourFoods({DateTime? now})` returns `YourFoods`, the
resolved and ordered Your foods list. The controller calls it once per picker
opening (see [Controller lifecycle](#controller-lifecycle)), and every search in
that opening filters it in memory.

```dart
final class YourFoods {
  /// Food History rows first, in Food History order, then never-logged
  /// User Foods by lower-cased name. Not capped.
  final List<FoodPickerItem> items;

  /// The Last Portion for (foodSource, id), for Catalogue rows.
  Portion? lastPortionFor(FoodSource foodSource, String id);

  static const empty = YourFoods(...);
}
```

`loadYourFoods` builds it in this order:

1.  `listFoodHistory(now: now)`.
2.  **Resolve each record to its current Food**, in one read per source:
    *   `user`: `NutritionRepository.listActiveUserFoods()`, read once and
        indexed by id. This is also the source for step 3.
    *   `usda`: `PlatformFoodsRepository.getUsdaFoodById(id)` (the seed is in
        memory after its first load).
    *   `openFoodFacts`: `OpenFoodFactsRepository.localProductsByCodes(codes)`,
        one query for all the Open Food Facts records.
    *   Any other Food Source: not resolved.

    A resolved record becomes a `FoodPickerItem` with `origin`
    `FoodPickerOrigin.history`, the current Food's name, nutrients, liquid
    flag, serving, package size and (for Open Food Facts) brand, plus the
    record's `lastPortion` and `lastLoggedAt`.
3.  **Unresolved records** (a User Food whose row is missing, a product no
    longer on the device, or a Food Source with no catalogue) fall back to the
    snapshot of their latest Food Entry: one
    `NutritionRepository.listFoodEntriesByIds(latestEntryIds)` call for all of
    them. The row takes the entry's name, nutrients, liquid flag, serving and
    package size; it has no brand. Logging it writes a snapshot of that
    snapshot, which is what Recent does today for every row.
4.  **Never-logged User Foods**: the active User Foods from step 2 whose
    (`user`, id) is not in Food History, ordered by lower-cased name. They have
    `origin` `FoodPickerOrigin.userFood` and no Portion.

Typed and filtered searches never call `loadYourFoods`; they take the loaded
`YourFoods` as an argument.

**Staleness.** Your foods is read when the picker opens. A Food Entry synced in
while the picker is open does not reorder the list until the next opening.
Editing a User Food, logging, and bundle installs all happen outside the
picker, so the next opening sees them.

### Search, per filter

```dart
Future<List<FoodPickerItem>> search({
  required AddFoodPickerFilter filter,
  required String query,
  required YourFoods yourFoods,
});
```

The `limit` parameter is removed. The limits are named constants in
`add_food_repository.dart`:

| Constant | Value | Use |
| :------- | :---- | :-- |
| `yourFoodsLimit` | 200 | Rows of Your foods on a blank All query and in the Your foods filter |
| `yourFoodsInSearchLimit` | 20 | Your foods rows in a typed All search |
| `searchResultLimit` | 50 | Total rows in a typed All search; rows in the USDA and Open Food Facts filters |

**Matching Your foods.** An item of `yourFoods.items` matches a typed query
when `foodNameMatchesQuery(item.name, query)` is true, or when its
`foodSource` is Open Food Facts and its id is one of `barcodeCandidates(query)`.
On a blank query every item matches.

| Filter | Query | Result |
| :----- | :---- | :----- |
| `all` | blank | The first `yourFoodsLimit` items of Your foods. The Catalogue is not searched. |
| `all` | typed | Built from the groups below, then deduplicated, then capped at `searchResultLimit`. |
| `yours` | any | The first `yourFoodsLimit` matching items of Your foods. |
| `usda` | any | `searchUsdaFoods(query, limit: searchResultLimit)`, as today. |
| `openFoodFacts` | blank | No rows. |
| `openFoodFacts` | typed | `searchLocal(query, limit: searchResultLimit)`, as today: barcode matches first, then FTS5 matches. |

**Typed All, the groups in order:**

1.  `Y`: the first `yourFoodsInSearchLimit` matching items of Your foods.
2.  `B`: the barcode matches. `searchLocal(query, limit: searchResultLimit)`
    is called once; `B` is its items whose id is in `barcodeCandidates(query)`.
3.  `U`: `searchUsdaFoods(query, limit: searchResultLimit)`.
4.  `F`: the remaining items of the same `searchLocal` result (the FTS5
    matches in `bm25` order).

USDA (`U`) and Open Food Facts (`searchLocal`) run concurrently
(`Future.wait`). The groups are concatenated in the order `Y`, `B`, `U`, `F`.
Duplicates are removed by the picker key (`foodSource`, id), keeping the first
occurrence. Because `Y` comes first, a Food in Your foods appears once, as its
Your foods row, and an Open Food Facts product that matches by barcode and is
in Your foods appears as its Your foods row. The list is then capped at
`searchResultLimit`.

USDA comes before Open Food Facts because USDA Foods are generic ("Milk,
whole"), and a one-word query is often meant for the generic Food rather than a
branded product containing that word. With three Foods in the seed today, this
rarely shows.

**Last Portions on Catalogue rows.** In every filter, a Catalogue row (`origin`
`usda` or `openFoodFacts`, including live results) takes its Last Portion from
`yourFoods.lastPortionFor(foodSource, id)`. A Catalogue Food with a Last Portion
has been logged, so it is in Food History; the lookup is in memory and needs no
query.

**Source failures.** In a typed All search, a failure in one source does not
fail the search. If `searchLocal` throws, `B` and `F` are empty; if
`searchUsdaFoods` throws, `U` is empty. The picker shows no error for a
failed group, as it shows none for a failed device reload today
(`_reloadDeviceMatches`). `search` throws only when every group it reads has
failed.

### Picker items

`FoodPickerItem.filter` is replaced by `FoodPickerItem.origin`:

```dart
enum FoodPickerOrigin { history, userFood, usda, openFoodFacts }
```

| Origin | Leading icon | Used for |
| :----- | :----------- | :------- |
| `history` | `Icons.history` | A Food History row, from any Food Source |
| `userFood` | `Icons.person_outline` | A never-logged User Food |
| `usda` | `Icons.public` | A USDA Catalogue row |
| `openFoodFacts` | `Icons.qr_code_scanner` | An Open Food Facts Catalogue row from the device or a live search |

`foodSource` names where a Food's data comes from. `origin` names why the row is
in the list, and the live merge depends on it (see
[Submitting the query](#submitting-the-query)).

**The picker key.** `FoodPickerItem.key` is the string
`'<foodSource.name>:<id>'`. It is the one identity used for deduplication, for
excluding live results that are already listed, and for widget keys.
`AddFoodPicker.resultKey(FoodPickerItem item)` returns
`Key('nutrition.addFood.result-${item.foodSource.name}-${item.id}')`.
`filterChipKey` keeps its form (`nutrition.addFood.filter-<filter.name>`).

`FoodPickerItem.lastLoggedAt` is the Food History record's `lastLoggedAt` for
`history` rows and null otherwise. Only the picker reads it.

### Controller lifecycle

`addFoodPickerControllerProvider` becomes
`AsyncNotifierProvider.autoDispose<AddFoodPickerController, AddFoodPickerState>`,
with the controller extending `AutoDisposeAsyncNotifier`, following the
transient-picker convention in
`apps/mobile/lib/features/template_picker/controllers/template_picker_controller.dart`.
The picker sheet is the only listener, so closing the sheet disposes the
controller, and the next opening builds a fresh one with filter `all`, an empty
query and a fresh `loadYourFoods`.

`build()` calls `loadYourFoods()` and keeps the result in a field. If it
throws, the field is `YourFoods.empty` and the picker still searches the
Catalogue, as `build()` already does when settings fail to load. Every `_load`, `_refresh` and
`_reloadDeviceMatches` passes the field to `search`.

### The picker, top to bottom

The header (the "Add Food" title, the **Scan barcode** button and the **Quick
add** button), the search field and the chips keep their place and styling.
The search field is not auto-focused, so the keyboard does not cover Your
foods when the picker opens. The compact attribution notice is removed from
under the chips.

Below the chips, the list depends on the filter and the query:

**All, blank query:**

*   If Your foods is not empty, the label "Your foods" (`label` style,
    `textSecondary`), then its rows (up to `yourFoodsLimit`).
*   If Your foods is empty, the line "Search by name or brand, or scan a
    barcode." (secondary text). The header's **Scan barcode** button is the
    scan action; there is no second button.

**All, typed query, in this order:**

1.  The rows of the typed All search, as one list with no group labels.
2.  If the list is empty, the line "No foods match." (secondary text).
3.  The bundle line, if the bundle status is `installing` or `failed`, with the
    texts from [Open Food Facts Integration](open-food-facts.md#the-picker-the-scanner-and-the-log-portion-screen).
4.  The online slot. It has the same states as today, and its row label
    becomes `Search Open Food Facts online for "<query>"`.
5.  The "From Open Food Facts" live group, as today.
6.  The attribution footer (below).

**Your foods filter:** the rows under no label. For a blank query with Your
foods empty, the line "Foods you log or create appear here." For a typed query
with no match, "No foods match."

**USDA filter:** the rows, or "No foods match."

**Open Food Facts filter:** today's layout (the bundle line, the device's
matches, the online slot, the live group) with three changes. A blank query
shows "Search Open Food Facts by product name, brand or barcode." in place of
"Type a product or brand name." The online row uses the new label. The
attribution footer replaces the top notice.

**Rows.** Each row keeps today's `_FoodResultRow` layout: the leading origin
icon, the name, the brand when known, and a `Wrap` of `FoodSourceBadge` (with
`showLicense` for Open Food Facts) and the kcal-per-100 label. A row with a
Last Portion adds a third item to the `Wrap`, "Last: <portion>", in the same
style as the kcal label. `<portion>` is the existing Food Entry amount text,
`'${portion.entered} ${portionUnitLabel(portion.unit)}'`, which
`nutrition_day_view.dart` builds in `_formatFoodEntryAmount`. That expression
moves to a public `formatPortionAmount(Portion)` in
`apps/mobile/lib/features/nutrition/widgets/portion_text.dart`, and both the
day view and the picker call it. Because it is a `Wrap`, the badge, the kcal
and the Last Portion wrap onto further lines at large text scales instead of
being cut off.

**The attribution footer.** One rule: when the list built for the current
filter and query (device rows and live rows together) contains at least one row
whose `foodSource` is Open Food Facts, `OpenFoodFactsAttributionNotice(compact:
true)` follows the last list item. Otherwise there is no footer. Its text and
links are unchanged, and it scrolls with the list. A blank All query whose
Your foods include an Open Food Facts Food therefore shows the footer too. Each
Open Food Facts row also keeps its "ODbL" badge, and the log-portion screen
keeps the full notice, the product link and the disclaimer. These three places
together carry the attribution
[Open Food Facts Integration § The licence, in short](open-food-facts.md#the-licence-in-short)
requires: the source's name, the licence and a link.

### Submitting the query

The keyboard's search action and the online row:

| Filter | Behaviour |
| :----- | :-------- |
| `all`, `openFoodFacts` | Today's Open Food Facts behaviour, gated by the "Look up foods online" setting: a barcode match opens; a barcode miss sends one live product request; otherwise one live search. |
| `yours`, `usda` | Runs the local search only and returns `null`, as Recent, Your Food and USDA do today. |

**The live merge.** `_mergeLiveResults` changes in two ways:

*   It replaces a device row with a newer live copy only when the row's `origin`
    is `openFoodFacts`. A `history` row is never replaced, because its facts
    already come from the current device copy, and a live copy is stored on
    the device when the user opens it.
*   It leaves out of the live group any live result whose picker key equals the
    key of a row in the list. Today it compares ids only.

### Agent surface

Food History is a new read of the user's data, so agents get it, per
[AGENTS.md](../../AGENTS.md) (the agent surface gets the same operations as the
app). The unified search itself stays a presentation of reads agents already
have (`listAgentFoods`, `searchAgentPlatformFoods`); see
[Alternative E](#alternative-e-a-unified-agent-search-operation).

**REST.** `GET /agent/foods/history`, `operationId` `listAgentFoodHistory`, tag
`Agent Reads`, bearer auth, defined in `apps/server/src/agent-food-history.ts`.

*   Summary: "List the user's Food History: the Foods they log, most often in
    the last 90 days first."
*   Description: "Returns the distinct Foods the caller has logged, derived on
    each call from live Food Entries and Meals and never stored, in the same
    order the app's add-food picker uses: Food Entries in the last 90 days
    descending, then the most recent Meal, then position in that Meal. Each item
    carries the Food Source and Food id to look the Food up with
    listAgentFoods or searchAgentPlatformFoods, the name the Food had when it
    was last logged, and its Last Portion. Archived User Foods are left out.
    Bounded by limit."
*   Query: `limit` (integer 1–200, default 50).
*   Response `AgentFoodHistoryResponse`:
    `{ items: AgentFoodHistoryItem[], limit: number, totalMatched: number }`.
    `AgentFoodHistoryItem`: `foodSource` (string, a Food Source name such as
    `openFoodFacts`, as `AgentMealEntry.foodSource` carries it), `foodId`
    (string), `lastLoggedName` (string, the latest entry's name),
    `recentCount` (integer ≥ 0), `lastLoggedAt` (ISO-8601 string),
    `lastPortion` (`{ value: number, entered: string, unit: string }` or null,
    the shape of `AgentMealEntry.portion`).
*   Errors: 401, 429 and 503 exactly as `listAgentMeals` declares them.
*   Store: `AgentFoodHistoryReadStore.listFoodHistory({ userId, limit, now })`
    reads the user's live `food_entries` and `meals` rows and the ids of
    archived `foods`, using the payload readers `readFoodEntriesByMealId` uses,
    and calls the pure function below.
*   Pure function: `buildFoodHistory({ entries, meals, archivedUserFoodIds,
    now })` in `apps/server/src/food-history.ts`, which applies
    [the rules above](#food-history) and returns the full ordered list. It is
    the TypeScript side of the golden vectors.

**MCP.** Tool `agent_list_food_history` in `apps/server/src/agent-mcp.ts`,
title "List Agent Food History", the REST description, the input `{ apiKey?,
limit? }`, the output `AgentFoodHistoryResponse`, through the same store and
the same unavailable error as `agent_list_meals`.

**Contract diff.** `openapi.json` gains the path, the two schemas and the
operation; `agent-client.ts` gains `listAgentFoodHistory`; the Dart API client
gains the matching method; `agent-skills/perennia/references/api-operations.md`
gains its generated row. `packages/contract/src/agent-skill-reference.ts` gains
`listAgentFoodHistory: "list-food-history"` and
`listAgentFoodHistory: "agent_list_food_history"` in its two maps. No existing
operation changes.

### Invariants

| Invariant ([AGENTS.md](../../AGENTS.md#non-negotiable-invariants)) | How it holds |
| :------------------------------------------------------------------ | :----------- |
| Local writes never block on the network. | Nothing on the picker writes, except storing an opened live copy in the background, which is unchanged. Typing sends nothing. |
| Food Entries are self-describing. | Food History reads Food Entries and changes none. Logging from a Your foods row writes a new snapshot of the current Food. |
| Derived analytics are computed, never stored or synced. | Food History, `recentCount` and the order are computed on each read, in the app and on the server, and never stored or synced. The app holds one read per picker opening in memory and drops it when the picker closes. |
| User-facing delete = archive. | Archived User Foods are left out of Your foods and of the agent read; their Food Entries stay. |
| Restore/import is merge-only; sync is silent LWW (last write wins). | Not touched. Synced entries count in Food History like any other entry. Imported entries have no `foodId` and do not count. |
| Validation is one shared module. | No rule or tier changes. |
| No behavioral analytics. | Food History is read from the user's own data, on the device or in their own account on the server, and is never sent anywhere else. |

### Vocabulary

[CONTEXT.md](../../CONTEXT.md) changes, in the implementation pull request:

*   **Food History (new):** the distinct Foods a user has logged, derived from
    their active Food Entries (one per Food Source and Food), each with how
    many times it was logged in the last 90 days, when it was last logged, and
    its Last Portion. It is ordered by that count, then by recency. It is
    computed, never stored. It orders Foods; a Food's facts come from the Food
    itself. In the add-food picker it appears as "Your foods", together with
    the user's active User Foods that have never been logged.
*   **Last Portion (new):** the Portion of the user's latest Food Entry for a
    Food that has a Portion, latest by the Meal's start, then the entry's last
    change.

### Validation and analytics

*   No validation rule or tier changes.
*   No nutrition analytic changes. Totals and trends keep reading Food Entry
    snapshots.
*   **Golden vectors.** Food History is computed in Dart (the picker) and in
    TypeScript (the agent read), so the two must agree.
    `packages/golden-vectors/vectors/m37-food-history.json` (domain
    `food-history`) holds cases of `{ meals, entries, archivedUserFoodIds,
    now }` and the expected ordered `{ foodSource, foodId, recentCount,
    lastLoggedAt, lastPortion }` list. The cases cover:
    *   frequency over recency;
    *   the 90-day boundary (an entry exactly 90 days before `now` counts);
    *   a tie on `lastLoggedAt` broken by position;
    *   the latest entry chosen by Meal `startedAt`, not `updatedAt`;
    *   Last Portion from an earlier entry when the latest has none;
    *   deleted entries, deleted Meals, Quick Entries, a null `isLiquid` and
        archived User Foods left out;
    *   one `foodId` under two Food Sources giving two records.

    The Dart runner inserts each case into an in-memory database and calls
    `listFoodHistory`; the TypeScript runner calls `buildFoodHistory`.

## Risks and Mitigations

| Risk | Mitigation |
| :--- | :--------- |
| Food History is slow for a user with years of logging. | Read once per picker opening, not per keystroke; measured below; a performance budget test fails the build if it regresses. |
| One source fails and the user sees nothing. | Each source fails alone (see [Source failures](#search-per-filter)); a failed `loadYourFoods` leaves the Catalogue searchable. |
| A logged Food is no longer on the device (for example a product dropped from a bundle refresh). | The row falls back to its last snapshot, so it stays loggable. |
| The Dart and TypeScript orders drift. | Golden vectors run in both languages in the `golden` job. |
| The All filter's search action sends live requests where Recent did not. | The "Look up foods online" setting still gates every live request, and nothing is sent while typing. |

## Alternatives Considered

### Alternative A: Keep source-first and fix the empty states

Show popular bundle products on the Open Food Facts chip before typing, and
default to it for new users. This was rejected because it fixes one chip and
keeps the decision the user should not have to make. A returning user would
still pick Recent first.

### Alternative B: Sections per source in the All list

Use labelled groups ("Your foods", "USDA", "Open Food Facts") while typing.
This was rejected for the typed list because the badge already names the
source, and labels add three non-tappable rows on a small screen. It is kept
for the blank query, where "Your foods" is the only group and explains why
those rows are there.

### Alternative C: All-time frequency, or recency only

All-time counts let a Food logged daily two years ago outrank this month's
staples. Recency alone (today's Recent order) puts a one-off snack above the
daily oat milk. A 90-day count with recency as the tie-break follows current
habits and still keeps every Food findable.

### Alternative D: Interleave the Catalogue by a shared score

Score USDA and Open Food Facts rows together, for example by normalising
`bm25` and a USDA text-match score. This was rejected because the two sources
use different match rules on purpose (see
[Open Food Facts Integration § Search and barcode rules](open-food-facts.md#search-and-barcode-rules)),
so any shared score would be invented. A fixed order is predictable and needs
no tuning.

### Alternative E: A unified agent search operation

Add `GET /agent/foods/search` that returns the same merged list. This was
rejected: the merge is a presentation for a person on a phone, and an agent
can compose it from `listAgentFoods`, `searchAgentPlatformFoods` and
`listAgentFoodHistory`. Food History, unlike the merge, is new data, so it gets
its own operation.

### Alternative F: Query Food History on every keystroke

The first draft read Food History on every search call. It was rejected after
measuring: the query takes 81–93 ms on the development machine with 20,000
entries (see [Performance](#performance)), which a phone would multiply, and
the text filter does not depend on the database. Reading once per opening costs
one query and accepts that a Food Entry synced in while the picker is open
appears at the next opening.

### Alternative G: Food History from Food Entry snapshots

The first draft took each Your foods row's facts from the latest Food Entry
snapshot. It was rejected in review: an edited or renamed User Food or Recipe
would be offered with its old values and old name, and the stale row would
hide the current one in search. CONTEXT.md makes the Food the input template
and the Food Entry a snapshot of it, so the picker reads the Food.

### Alternative H: A "See all your foods" preview

The first draft showed 20 Your foods rows on a blank All query and a "See all
your foods" row that switched to the Your foods chip. It was rejected: the row
needed a "has more" signal from the repository and a second limit, and a lazy
list of up to 200 rows costs the same reads. The Your foods chip remains for
narrowing a typed search to the user's own Foods.

### Alternative I: Hide the USDA chip while the seed is tiny

The barcode not-found state's **USDA** action selects the USDA filter, so
hiding the chip would change that state, which this spec leaves alone. Retiring
the chip and the action together belongs to the spec that grows or replaces
the seed.

## Non-Functional Requirements

### Performance

Measured on 2026-10-31 on the development machine (an Apple Silicon Mac, Drift
in memory, `flutter test`) with 20,000 Food Entries across 1,500 Foods in 3,400
Meals, about five years of logging around eleven Foods a day:

| Query | Time |
| :---- | :--- |
| The Food History query above (counts, latest entry, Last Portion) | 81–93 ms |
| A grouped count without the Last Portion | 17–26 ms |

The query reads every active Food Entry once, so an index on
`food_entries (food_source, food_id)` would not shorten it, and none is added.

*   `listFoodHistory` with that data runs within `foodHistoryBudget` (150 ms)
    on the test host. The constant is added to
    `apps/mobile/test/performance/performance_budget_thresholds.dart`, and the
    test to `performance_budgets_test.dart`.
*   A typed All search, given a loaded `YourFoods` of 1,500 items and the
    41,000-product synthetic bundle the existing Open Food Facts budget test
    builds, returns within the existing `openFoodFactsLocalSearchBudget`
    (100 ms) on the test host.
*   `loadYourFoods` runs once when the picker opens. The picker shows its
    loading state until it returns; typing during that time is debounced as
    today.

### Accessibility

*   Every new tappable row and button is at least 48 dp tall
    (`AppDimens.touchTarget`).
*   Rows keep their whole content at a text scale of 2.0; the test checks that
    the badge, kcal and Last Portion texts are all found and none overflows.
*   The "Your foods" label is a semantics header.
*   Colour is never the only signal: the source is a text badge, and the origin
    icon is decorative.
*   **The row's semantics label.** Each row is wrapped in
    `Semantics(button: true, label: <label>, excludeSemantics: true)`, so a
    screen reader reads the label once and not the child texts again. The
    label joins the parts that exist with ", ":
    `<name>, <brand>, <source label>, <kcal text>, Last <portion>`. The source
    label is the badge's text without the licence marker (for example "Open
    Food Facts"). The kcal text is the row's kcal label as displayed. A row
    with no brand or no Last Portion leaves that part out. Example: "Oat milk,
    Oatly, Open Food Facts, 46 kcal per 100 ml, Last 250 ml".

### Privacy

*   No new data leaves the device. The live-request rules of
    [Open Food Facts Integration § Live requests](open-food-facts.md#live-requests)
    are unchanged, and nothing is sent while typing.
*   The agent read returns only the calling user's own data, to an agent that
    user authorised with an API key, as every agent read does.

### Rollout and rollback

*   No flag. The app change and the new agent operation ship in one pull
    request. Rolling back is reverting it; no data is migrated in either
    direction, and removing the operation removes no stored data.

## Future Improvements

*   Phase 2, browsing by Aisle: [Food Aisles](food-aisles.md).
*   A larger USDA seed, which would make the USDA rows useful in All.
*   Ordering Your foods per Meal (breakfast staples at breakfast), after phase
    1 has shown whether the 90-day order is enough on its own.

## Detailed Implementation Plan

One pull request. It links this spec and sets its Status to **Current**. It is
built in four phases; each phase ends with the named tests green and the app
building.

### Phase 1: Food History, app and golden vectors

#### 1. `apps/mobile/lib/domain/nutrition/nutrition.dart` (Modify)

Add `FoodHistoryRecord` next to `FoodEntryRecord`, with the fields and types
under [Food History](#food-history), all `final`, and a `const` constructor
requiring all of them except `lastPortion`.

#### 2. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

In `NutritionRepository`:

*   Add `Future<List<FoodHistoryRecord>> listFoodHistory({DateTime? now})`
    running the query under [Food History](#food-history) through
    `_database.customSelect`, with a docstring stating that it is an ordering
    signal, the 90-day window, the order, and that archived User Foods are
    left out and why.
*   Add `Future<List<FoodEntryRecord>> listFoodEntriesByIds(List<String> ids)`,
    returning the entries with those ids in any order (one `isIn` query; an
    empty list returns an empty list without a query).
*   Remove `listRecentFoodEntries`, `lastPortionForFood` and
    `lastPortionsForFoods`. Their only callers are in
    `add_food_repository.dart`, which this pull request rewrites.

#### 3. `packages/golden-vectors/vectors/m37-food-history.json` and `m37-food-history.schema.json` (Create)

The cases under [Validation and analytics](#validation-and-analytics), with a
JSON Schema for the case shape, following `m34-routine-up-next.json` and its
schema. Times are ISO-8601 UTC strings; Portions use the Portion JSON the app
stores in `portion_json`.

#### 4. `apps/mobile/test/domain/food_history_golden_test.dart` (Create)

For each case: an in-memory `AppDatabase`, the case's Meals, Food Entries and
archived User Food rows inserted through the database, then
`listFoodHistory(now: case.now)` compared to the expected list. Register the
domain in `_dartRunnerByDomain` in
`apps/mobile/test/domain/golden_vector_ownership_test.dart`.

#### 5. `apps/mobile/test/features/nutrition/nutrition_repository_test.dart` (Modify)

Add a `group('food history', ...)` with the repository tests in the
Verification Plan. There are no `listRecentFoodEntries` tests to remove.

**Phase 1 checkpoint:** `flutter test test/domain/food_history_golden_test.dart
test/features/nutrition/nutrition_repository_test.dart` passes. The app does
not build yet, because `add_food_repository.dart` still calls the removed
methods; phase 2 fixes that, so commit phases 1 and 2 together if a commit
must build.

### Phase 2: Repositories

#### 6. `apps/mobile/lib/data/repositories/open_food_facts_repository.dart` (Modify)

Add `Future<List<PlatformFoodRecord>> localProductsByCodes(List<String>
codes)` to the interface, the implementation (through the existing
`database.productsByCodes`, mapped as `searchLocal` maps rows) and
`StubOpenFoodFactsRepository` (returns an empty list).

#### 7. `apps/mobile/lib/features/nutrition/widgets/portion_text.dart` (Create)

`String formatPortionAmount(Portion portion)`, returning
`'${portion.entered} ${portionUnitLabel(portion.unit)}'`. Change
`_formatFoodEntryAmount` in `nutrition_day_view.dart` to call it.

#### 8. `apps/mobile/lib/features/nutrition/repositories/add_food_repository.dart` (Modify)

*   Replace `AddFoodPickerFilter`'s values with `all, yours, usda,
    openFoodFacts` and labels All, Your foods, USDA, Open Food Facts.
*   Add `FoodPickerOrigin`. Replace `FoodPickerItem.filter` with `origin`. Add
    the `key` getter.
*   Add `YourFoods` and the three limit constants.
*   Add `loadYourFoods({DateTime? now})` to the interface and to
    `RepositoryAddFoodRepository`, per [Your foods](#your-foods).
*   Change `search` to the signature under
    [Search, per filter](#search-per-filter) and implement the table, the
    typed All groups, the dedupe, the Catalogue Last Portion lookup and the
    source-failure rule. Remove `_searchRecent` and `_searchUserFoods`. Change
    `_openFoodFactsItems` and `_searchUsdaFoods` to take Last Portions from
    `YourFoods` instead of querying.
*   `searchOnline` and `lookupBarcode` gain a required `YourFoods yourFoods`
    argument, used only for Last Portions.

#### 9. `apps/mobile/test/features/nutrition/add_food_repository_fakes.dart` (Modify)

The `NoOnlineLookups` mixin gains `loadYourFoods` returning `YourFoods.empty`.
Each fake's `search` override takes the new signature.

#### 10. `apps/mobile/test/features/nutrition/add_food_repository_test.dart` (Modify)

Rewrite the filter tests for the new filters and merge rules (listed in the
Verification Plan).

**Phase 2 checkpoint:** `flutter test test/features/nutrition/add_food_repository_test.dart`
passes and `flutter analyze` reports no errors in `lib/` outside the controller
and widget files that phase 3 changes.

### Phase 3: Controller and picker

#### 11. `apps/mobile/lib/features/nutrition/controllers/add_food_controller.dart` (Modify)

*   Make the provider and controller `autoDispose` per
    [Controller lifecycle](#controller-lifecycle).
*   Add a `YourFoods _yourFoods` field loaded in `build()`, and pass it to
    every `search`, `searchOnline` and `lookupBarcode` call.
*   Change the initial `_filter` to `AddFoodPickerFilter.all`.
*   In `submitQuery`, change the `_filter != openFoodFacts` early return so
    that `all` takes the Open Food Facts path too.
*   Change `_mergeLiveResults` per [Submitting the query](#submitting-the-query),
    comparing `FoodPickerItem.key`.
*   Update the docstrings that name the Open Food Facts filter alone.

#### 12. `apps/mobile/lib/features/nutrition/widgets/add_food_picker.dart` (Modify)

*   Implement [The picker, top to bottom](#the-picker-top-to-bottom): remove
    the top attribution block; branch `_FoodResults` on filter and blank query;
    add the Your foods label, the new-user line, the bundle line's place in
    All and the attribution footer rule.
*   Change the online row label.
*   Change `_sourceIcon` to switch on `origin`. Change `resultKey` to take a
    `FoodPickerItem`.
*   Add the Last Portion text to `_FoodResultRow` through
    `formatPortionAmount`, and the row `Semantics` wrapper and label per
    [Accessibility](#accessibility).
*   Add keys: `yourFoodsLabelKey` (`nutrition.addFood.yourFoodsLabel`),
    `emptyStateKey` (`nutrition.addFood.emptyState`), `noMatchLineKey`
    (`nutrition.addFood.noMatch`) and `attributionFooterKey`
    (`nutrition.addFood.attributionFooter`). Keep `emptyQueryLineKey` for the
    Open Food Facts blank-query line.

#### 13. Picker test files (Modify)

*   `apps/mobile/test/features/nutrition/add_food_picker_state_test.dart`: the
    controller tests in the Verification Plan; its fakes take the new
    signatures.
*   `apps/mobile/test/features/nutrition/add_food_picker_test.dart`: the widget
    tests in the Verification Plan. `_OnlineAddFoodRepository`, which does not
    use the shared mixin, gains `loadYourFoods` and the new signatures.
*   `apps/mobile/test/features/nutrition/nutrition_day_view_test.dart`: its
    three fakes take the new signatures; add the CUJ 1 end-to-end test.
*   `apps/mobile/test/features/nutrition/log_portion_screen_test.dart`: update
    filter and origin names.

#### 14. `apps/mobile/test/performance/performance_budget_thresholds.dart` and `performance_budgets_test.dart` (Modify)

Add `foodHistoryEntryCount = 20000`, `foodHistoryFoodCount = 1500`,
`foodHistoryBudget = Duration(milliseconds: 150)`, and the two budget tests
under [Performance](#performance). Add a sentence for each to
`apps/mobile/test/performance/README.md`.

**Phase 3 checkpoint:** `pnpm ci:local mobile` passes.

### Phase 4: Agent operation and documents

#### 15. `apps/server/src/food-history.ts` (Create)

`buildFoodHistory` per [Agent surface](#agent-surface), with input types for
the Meal and Food Entry fields it reads and a docstring pointing at this spec.

#### 16. `apps/server/src/agent-food-history.ts` (Create)

The query and response Zod schemas (`AgentFoodHistoryQuerySchema`,
`AgentFoodHistoryItemSchema`, `AgentFoodHistoryResponseSchema`), the route
`agentFoodHistoryRoute`, the store type `AgentFoodHistoryReadStore` and
`createDrizzleAgentFoodHistoryReadStore(db)`.

#### 17. `apps/server/src/app.ts` and `apps/server/src/index.ts` (Modify)

Register the route in `app.ts` next to `agentMealListRoute`, with the same
auth, rate limit and unavailable handling, taking the store as an app option
as `agentNutritionReadStore` is taken. In `index.ts`, create it with
`createDrizzleAgentFoodHistoryReadStore(db)` next to the
`createDrizzleAgentNutritionReadStore` call, and pass it to the app and to the
MCP server.

#### 18. `apps/server/src/agent-mcp.ts` (Modify)

Register `agent_list_food_history` per [Agent surface](#agent-surface), next
to `agent_list_meals`.

#### 19. `packages/contract/src/agent-skill-reference.ts` (Modify), then the generated files

Add the two map entries. Run `corepack pnpm --filter @perennia/contract
generate` and commit `packages/contract/openapi.json`,
`packages/contract/src/agent-client.ts`,
`apps/mobile/lib/api/perennia_api_client.dart` and
`agent-skills/perennia/references/api-operations.md`.

#### 20. Server tests (Create)

*   `apps/server/test/food-history.golden.test.mjs`: runs every
    `m37-food-history.json` case through `buildFoodHistory`.
*   `apps/server/test/agent-food-history.test.mjs`: against Postgres, the
    route returns the seeded user's order, honours `limit`, leaves out another
    user's entries and archived User Foods, and returns 401 without a key; the
    MCP tool returns the same body.

#### 21. `tools/ci-local.mjs` and `.github/workflows/ci.yml` (Modify)

Add `apps/server/src/food-history.ts` and
`apps/server/test/food-history.golden.test.mjs` to the `golden` job's paths and
commands in both files, in the same commit.

#### 22. `CONTEXT.md` (Modify)

Add **Food History** and **Last Portion** as worded under
[Vocabulary](#vocabulary).

#### 23. `docs/designs/open-food-facts.md` (Modify)

*   At the start of "The picker, the scanner and the log-portion screen", add
    one paragraph saying the picker's layout, filters and attribution
    placement are superseded by this spec, and the scanner, the log-portion
    screen and the About screen text are unchanged.
*   Replace each remaining mention of the Recent filter in that document with
    a reference to Your foods in this spec.

#### 24. `docs/designs/SITEMAP.md` (Modify)

Set this spec's row (added in the spec pull request) to Current.

**Phase 4 checkpoint:** the full gate below passes.

## Verification Plan

**The gate:** `pnpm ci:local mobile js contract golden` must pass. `mobile`
runs the app tests and analysis; `js` runs the server tests against an
ephemeral Postgres (Docker required); `contract` checks that the generated
files match the routes; `golden` runs the vectors in both languages. The jobs
are defined in [tools/ci-local.mjs](../../tools/ci-local.mjs) and
[docs/development.md](../development.md). `sync` is unaffected and runs in the
full gate before merge.

**Golden vectors (`food_history_golden_test.dart`,
`food-history.golden.test.mjs`):** every `m37-food-history.json` case passes in
both languages.

**Repository, against in-memory SQLite (`nutrition_repository_test.dart`):**

*   Two Foods, one logged 5 times in the last 90 days and one logged 10 times
    more than 90 days ago: the first ranks first, and the second is still
    listed.
*   Equal `recentCount`: the more recently logged Food ranks first. Two Foods
    in the same Meal: ordered by position.
*   `latestEntryId` and `lastPortion` come from the entry with the latest Meal
    `startedAt`, not the latest `updatedAt`. If the latest entry has no
    Portion, the previous entry's Portion is used.
*   Entries in a deleted Meal, deleted entries, Quick Entries, entries with a
    null `isLiquid` and entries of an archived User Food are left out. An
    archived User Food's entries are still returned by
    `listActiveEntriesForMeal`.
*   The same `foodId` under two Food Sources gives two records.
*   `now` is injectable: an entry exactly 90 days before `now` counts.
*   `listFoodEntriesByIds` returns the requested entries and an empty list for
    no ids.
*   Kill-and-reopen: open `AppDatabase.openFile` on a temporary file, log an
    entry, close the database, open it again on the same file, and
    `listFoodHistory` returns the entry's Food with its Last Portion.

**Add-food repository (`add_food_repository_test.dart`):**

*   `loadYourFoods`: Food History rows first, then never-logged User Foods by
    lower-cased name, with more than 50 active User Foods all present.
*   An edited User Food appears with its current name and nutrients (CUJ 7); a
    search for its old name does not find it.
*   An Open Food Facts history row carries the current device product's name
    and brand.
*   A history record whose product is not on the device falls back to its
    latest entry's snapshot, with no brand.
*   All, blank query: Your foods rows only, up to 200.
*   All, typed: Your foods matches, then barcode matches, then USDA, then Open
    Food Facts FTS matches. A Food in both Your foods and the Catalogue appears
    once with `origin` `history`. A barcode query whose product is in Your
    foods returns that Your foods row first. Capped at 50, with at most 20
    Your foods rows.
*   A punctuation-only query is blank.
*   A throwing `searchLocal` still returns Your foods and USDA rows.
*   Your foods filter: up to 200 rows; a blank query returns all of them.
*   USDA and Open Food Facts filters: unchanged results, with `origin` set and
    Last Portions taken from `YourFoods`.

**Controller (`add_food_picker_state_test.dart`):**

*   It starts on `all` with an empty query, and calls `loadYourFoods` once
    across several searches.
*   A failing `loadYourFoods` still serves Catalogue results.
*   Submitting in All with a name sends one live search; with a barcode it
    looks the barcode up; in Your foods it sends nothing; with online lookups
    off it sends nothing.
*   A live result never replaces a `history` row. A live result whose picker
    key is already listed is left out of the live group; one with the same id
    under another Food Source is kept.
*   Disposing the provider and reading it again starts on `all` with an empty
    query.

**Widgets (`add_food_picker_test.dart`):**

*   With history, a blank query shows the "Your foods" label and rows with
    "Last: …".
*   With no history and no User Foods, a blank query shows the empty-state
    line, no second Scan button and no attribution footer.
*   A list with an Open Food Facts row, typed or blank, shows the footer after
    the list. A list with no Open Food Facts rows has no footer.
*   The bundle `installing` line follows the rows of a typed All search.
*   The online row label reads `Search Open Food Facts online for "<query>"`.
*   Accessibility: every new tappable is at least 48 dp tall. At a text scale
    of 2.0 a row with a brand, a badge, kcal and Last Portion has no overflow.
    The "Your foods" label is a header in semantics. A row's semantics label
    matches the template, and its child texts are not separate semantics
    nodes.
*   Closing and reopening the picker after typing shows an empty query and All
    selected.

**Day view (`nutrition_day_view_test.dart`):**

*   CUJ 1 end to end: tap Add Food, tap the first Your foods row, and the
    log-portion screen opens with that Last Portion.

**Performance (`performance_budgets_test.dart`):** the two budgets under
[Performance](#performance).

**Server (`agent-food-history.test.mjs`):** the cases listed in file 20.
