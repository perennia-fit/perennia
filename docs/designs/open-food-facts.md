# Open Food Facts Integration

*   **Author:** Leonardo Pinheiro
*   **Status:** Draft
*   **Date:** 2026-10-25

--------------------------------------------------------------------------------

## Overview

Perennia's nutrition domain logs what a user eats. A **Food** is a catalogued
item with nutrition facts per 100 g or ml. A **Food Source** records where those
facts came from: USDA, Open Food Facts, the user, or an import. A **Food Entry**
is one logged item in a **Meal**, and it keeps a snapshot of the Food's facts
and source as they were when it was logged. These terms are defined in
[CONTEXT.md](../../CONTEXT.md). How the app, the server and the agent surface fit
together is in [ARCHITECTURE.md](../../ARCHITECTURE.md). The rules every spec
must keep are in [AGENTS.md](../../AGENTS.md), and the UI tokens are in
[DESIGN.md](../../DESIGN.md).

Open Food Facts (https://world.openfoodfacts.org) is a crowdsourced database of
packaged food products, keyed by barcode. The app already has a partial
integration with it: an Open Food Facts filter in the add-food picker, a barcode
scanner, a small device cache, and a source badge on each food. That
integration has defects (listed under The Problem), needs the network for
every new product, and has no equivalent on the agent surface.

This spec does four things:

1.  **Ships an offline bundle** of common products from five launch countries
    (Australia, the United States, the United Kingdom, Canada and New Zealand),
    so that search and barcode lookup work with no signal.
2.  **Fixes live search and lookup** so that they return lists, stay within
    Open Food Facts' published rate limits, identify Perennia, and use the
    current API version.
3.  **Makes the source visible and honest:** every Open Food Facts food shows
    its source and licence, links to its product page, and carries Open Food
    Facts' own accuracy disclaimer.
4.  **Gives agents the same catalogue,** through a REST operation and an MCP
    tool.

### The licence, in short

The Open Food Facts database is published under the Open Database License
(ODbL) 1.0. Individual values are under the Database Contents License (DbCL)
1.0, and product photos under CC BY-SA 3.0. ODbL asks for three things:

*   **Attribution.** Name Open Food Facts, name the licence, and link to
    openfoodfacts.org or the product's own page, wherever the data or something
    made from it is shown publicly.
*   **Share-alike.** A modified copy of the database that is used publicly must
    be offered under ODbL too. This covers data only; Perennia's code stays
    AGPL-3.0.
*   **Keep open.** A copy distributed in a restricted form (for example inside
    an encrypted app package) must also be available without the restriction.

The offline bundle is a modified copy (filtered and reshaped) that Perennia
distributes, so it is published under ODbL in the repository, with the script
that builds it. Perennia is open source, so these terms cost little; they are
recorded here so that later changes keep meeting them.

## The Problem

A user logging a branded food (a yogurt, a protein bar, a sports drink) today
runs into four failures.

1.  **No signal, no product.** Every Open Food Facts product the user has not
    looked up before needs the network. Gyms, basements and kitchens are often
    where the signal is worst. The bundled USDA catalogue, the only offline
    reference data, holds three generic foods. An offline user finds nothing
    but their own User Foods and their Recent list.
2.  **Search returns one product.** `OpenFoodFactsRepository.search()` keeps
    only the first usable product in the response
    (`apps/mobile/lib/data/repositories/training_repositories.dart`, around line
    2706). A search for "greek yogurt" shows a single yogurt, which is usually
    not the one in the user's hand.
3.  **The app breaks Open Food Facts' usage rules, and risks being blocked.**
    *   The picker searches 300 ms after the user stops typing
        (`add_food_controller.dart`, `searchDebounceDuration`). With the Open
        Food Facts filter selected, each pause sends a request. Open Food Facts
        allows 10 search requests per minute per device and names
        search-as-you-type as a way to be blocked.
    *   Requests carry no custom User-Agent. Open Food Facts asks every client
        to identify itself as `AppName/Version (ContactEmail)`.
    *   Barcode lookups use API v2, which Open Food Facts marks deprecated.
    *   Partial queries ("gre", "gree", "greek") each become a cache row,
        because the cache is keyed by query text and holds one product per
        query.
4.  **The source is shown, but not explained.** The badge says "Open Food
    Facts". Nothing tells the user that the values are crowdsourced and can be
    wrong, which Open Food Facts itself states: its data is indicative, not
    guaranteed accurate or complete, and "must not be used for medical
    purposes". There is no way to open the product's page to check or correct
    it.

Agents have a fifth problem. The server accepts Food Entries whose source is
Open Food Facts, but it offers no way to look a product up
(`apps/server/src/agent-foods.ts`, `search-platform-foods` covers USDA only). An
agent logging a branded food has to supply the nutrient values from somewhere
else, so the agent and the app can log the same barcode with different numbers.

## Goals

1.  **Offline search and barcode lookup for common products.** The app ships a
    bundle of Open Food Facts products. For each launch country (AU, US, UK, CA,
    NZ), it takes the 10,000 most-scanned products that have a product name and
    known energy, protein, carbohydrate and fat per 100 g or ml, and merges
    them into one set with no duplicate barcodes. With the network off:
    *   typing in the picker returns matching bundled products as the user
        types, within 100 ms on a mid-range device;
    *   scanning a bundled product's barcode finds it.
2.  **The bundle stays small.** It adds no more than 6 MB to the compressed
    app download on either platform.
3.  **Live search returns a list, and only when asked.** Live search runs when
    the user submits the query (the keyboard's search action or an explicit
    "Search online" control), never while typing. It returns up to 20 products
    per page and can load further pages.
4.  **One product, one row.** A barcode that exists in more than one place
    (the bundle, the device cache, a live result) appears once in the picker.
    The copy that Open Food Facts changed most recently wins.
5.  **Products seen once stay available offline.** Every product the app fetches
    live is cached on the device by barcode, and can then be searched and
    scanned offline.
6.  **The app follows Open Food Facts' rules.**
    *   Every request sends `User-Agent: Perennia/<app version> (<contact
        address>)`.
    *   The app sends at most 10 search requests and 15 product requests per
        minute. Requests over that limit are refused locally with a message,
        not sent.
    *   A 429 or 503 response shows "Open Food Facts is busy; try again in a
        minute" and is not retried automatically.
    *   Barcode lookups use the current product API (v3).
7.  **Every Open Food Facts food explains its source.** Wherever an Open Food
    Facts food is shown (the picker, the food detail, a logged Food Entry), it
    carries the source badge with "ODbL". The food detail also shows:
    *   a "View on Open Food Facts" link to that product's page;
    *   the disclaimer "Values come from Open Food Facts contributors and may be
        incomplete or wrong. Check the label. Not for medical use.";
    *   the date Open Food Facts last changed this product's data, for bundled
        and live products alike.

    The About screen states the same disclaimer and the bundle's dataset date.
8.  **Online lookups can be turned off.** A setting, "Look up foods online", is
    on by default. When it is off, the app sends nothing to Open Food Facts, and
    search and scanning use only the bundle and the device cache. This keeps
    the promise that the app is complete with no network.
9.  **Agents get the same catalogue.** A REST operation and an MCP tool search
    the same bundle and look a barcode up in it, and return the same record
    shape and attribution object the USDA operation already returns.
10. **The licence obligations are met in the repository.** The bundle file
    carries an ODbL notice. A third-party data notice at the repository root
    lists Open Food Facts and USDA with their licences. The script that builds
    the bundle from a pinned Open Food Facts export is committed, and running
    it again on the same export produces the same file.

## Non-Goals

*   **More USDA foods.** The USDA catalogue stays at its current three foods.
    Generic foods (rice, chicken, an apple) still need a separate data change,
    with its own spec.
*   **Bundles for other countries, or downloadable country packs.** Users
    outside the five launch countries get little from the bundle and rely on
    live search.
*   **Writing to Open Food Facts:** adding products, correcting values or
    uploading photos. The product link lets the user do that on the Open Food
    Facts site.
*   **Product photos.** They are under a different licence (CC BY-SA 3.0) and
    can show third-party trademarks.
*   **Scores and labels:** Nutri-Score, NOVA group, Eco-Score, ingredients and
    allergens. Allergen data in particular is safety information, and
    crowdsourced values must not be presented as reliable for it.
*   **Changing logged history.** When a product's values change (a newer bundle
    or a live refetch), existing Food Entries keep the snapshot they were logged
    with. This is the existing rule and stays as it is.
*   **Showing the user how bundled and live values differ.** The newer one is
    used, without a comparison view.
*   **A Food Library screen** on the Library root.
*   **A legal opinion.** Whether serving synced Food Entry snapshots through the
    agent API needs anything beyond the published code under ODbL section 4.6
    is to be checked by a lawyer before public release. It does not change this
    design.

## Open Questions

None open. The questions carried from the Goals were settled while drafting the
Technical Plan:

*   **Size budget:** estimated at about 2.5 MB, well inside 6 MB (see
    [Bundle size](#bundle-size)). Checked again against the real build before
    the bundle is committed.
*   **Live lookups on the server:** offered, but only when the agent asks for
    them with `online=true`, behind a server-wide request budget (see
    [Agent surface](#agent-surface)).
*   **Search endpoint:** the legacy `/cgi/search.pl` (see
    [Live requests](#live-requests)).
*   **Where the bundle file lives:** plain git (see
    [Where the bundle is stored](#where-the-bundle-is-stored)).
*   **Contact address:** set at build time, with the repository URL as the
    fallback (see [Live requests](#live-requests)).

## Critical User Journeys (CUJs)

### CUJ 1: Scan a common product with no signal

*   **Given**: the app is installed and the bundle is installed (see
    [Installing the bundle on the device](#installing-the-bundle-on-the-device)).
    The device has no network. The user holds a product that is in the bundle.
*   **When**: the user opens the add-food picker for a Meal, taps **Scan
    barcode**, and scans the product.
*   **Then**: the log-portion screen opens for that product with no network
    request and no spinner. It shows the product name, the brand, the source
    badge "Open Food Facts - ODbL", the product link, the disclaimer and the
    data date. Tapping **Log** saves a Food Entry whose snapshot carries
    `foodSource: openFoodFacts` and the product's values. Saving does not wait
    on anything but the local database.

### CUJ 2: Search the bundle while typing

*   **Given**: the bundle is installed. The network state does not matter.
*   **When**: the user selects the **Open Food Facts** filter in the picker and
    types "chobani gr".
*   **Then**: within 100 ms of the 300 ms typing pause, the list shows bundled
    and previously fetched products whose name or brand contains words starting
    with "chobani" and "gr", under the heading "On this device". No request
    goes to Open Food Facts while the user types.

### CUJ 3: Find a product that is not on the device

*   **Given**: the device is online, "Look up foods online" is on, and the
    product is in neither the bundle nor the device cache.
*   **When**: the user types its name and taps **Search Open Food Facts online**
    (or the keyboard's search action) in the Open Food Facts filter.
*   **Then**: one search request is sent. Up to 20 results appear under "From
    Open Food Facts", below any "On this device" matches, with no product shown
    twice. **Load more** fetches the next 20. Every product in the response is
    saved to the device cache. When the user later searches for it offline, it
    appears under "On this device".

### CUJ 4: Open Food Facts is busy, or the user searches too often

*   **Given**: the device is online and "Look up foods online" is on.
*   **When**: the user submits an 11th online search within 60 seconds, or Open
    Food Facts answers with HTTP 429 or 503.
*   **Then**: for the 11th search, no request is sent and the list shows "Online
    search is limited to 10 searches a minute. Try again in N seconds." For a
    429 or 503 it shows "Open Food Facts is busy. Try again in a minute." In both
    cases the "On this device" results stay on screen, nothing retries on its
    own, and Quick add stays available.

### CUJ 5: The user turns online lookups off

*   **Given**: the user turns off **Settings > Food data > Look up foods
    online**.
*   **When**: the user searches, submits a search, or scans a barcode that is
    not on the device.
*   **Then**: no request goes to Open Food Facts. The "Search Open Food Facts
    online" row is replaced by "Online lookups are off". A scanned barcode that
    is not on the device shows the existing not-found state, which offers Quick
    add and creating a User Food.

### CUJ 6: An agent finds and logs a branded product

*   **Given**: an agent has an API key for the user's account.
*   **When**: the agent calls `GET /agent/foods/platform-search?source=openFoodFacts&barcode=<code>`
    (or the MCP tool `agent_search_platform_foods` with the same input), then
    logs the result with the existing meal batch-write operation.
*   **Then**: for a bundled product, the response carries the same name, values,
    serving and package sizes, and data date the app shows for that barcode,
    plus an attribution object with the licence and disclaimer. No request goes
    to Open Food Facts unless the agent passed `online=true`.

### CUJ 7: A maintainer refreshes the bundle

*   **Given**: a newer Open Food Facts export exists.
*   **When**: a maintainer runs the bundle builder against a pinned revision of
    the export, checks the size report, and commits the new bundle file in a
    pull request.
*   **Then**: users who install the next app version get the new bundle on
    first launch. For a product the device had fetched live with a newer
    Open Food Facts change date than the new bundle's copy, the live copy is
    kept. Food Entries logged before the refresh keep their snapshots.

### CUJ 8: The app is killed while the bundle installs

*   **Given**: the first launch after an install or update has started
    installing the bundle.
*   **When**: the app is killed before the install finishes, and reopened.
*   **Then**: the install starts again from the beginning, and once it finishes
    the device holds exactly one complete copy of the bundle. Logging Sets, Food
    Entries and Doses worked throughout, because the bundle lives in a separate
    database file (see below).

## Technical Plan (Architecture)

### Overview of the parts

```text
 Maintainer, offline                     Repository
 ┌───────────────────────────┐   writes  ┌──────────────────────────────────────────┐
 │ tools/build-open-food-    │──────────▶│ apps/mobile/assets/seeds/                │
 │ facts-bundle.mjs          │           │   open_food_facts_bundle.ndjson.gz       │
 │  reads pinned OFF export  │           │   open_food_facts_bundle.LICENSE.md      │
 │  maps with shared TS code │           └──────────────┬──────────────┬────────────┘
 └───────────────────────────┘                          │ app asset     │ copied into the
                                                        ▼               ▼ server image
 App (device)                                      Server
 ┌──────────────────────────────────────────┐      ┌───────────────────────────────────┐
 │ Picker / scanner / log-portion screen    │      │ GET /agent/foods/platform-search  │
 │        │                                 │      │   source=openFoodFacts            │
 │        ▼                                 │      │ MCP agent_search_platform_foods   │
 │ OpenFoodFactsRepository                  │      │        │                          │
 │  ├─ FoodReferenceDatabase (own file)     │      │        ▼                          │
 │  │    products table + FTS5 index        │      │ in-memory SQLite (node:sqlite),   │
 │  │    rows from bundle and from live     │      │ same schema and same FTS query    │
 │  └─ OpenFoodFactsClient (HTTP)           │      │        │ only when online=true    │
 │       User-Agent, request budget         │      │        ▼                          │
 └───────┬──────────────────────────────────┘      │ OpenFoodFactsClient (server)      │
         │ search.pl / API v3 (user action only)   └───────┬───────────────────────────┘
         ▼                                                 ▼
                    world.openfoodfacts.org (live, rate-limited)
```

The two shared rules that keep the app and the server in step are pure
functions, written once in Dart and once in TypeScript and pinned by golden
vectors ([ARCHITECTURE.md](../../ARCHITECTURE.md), "Validation"):

1.  **Product mapping:** an Open Food Facts product object to a Perennia
    Platform Food (name, brand, nutrients, serving, package, liquid flag,
    change date), or to "excluded".
2.  **Search and barcode normalization:** a typed query to an FTS5 match
    expression, and a scanned code to the list of barcodes to try.

The bundle builder uses the TypeScript mapping, so the bundle, the app's live
path and the server's live path all produce the same record for the same
product.

### The bundle file

`apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz` is a gzip-compressed
file of JSON lines: one header line, then one line per product, sorted by
barcode in ascending string order.

Header line:

```json
{
  "format": "perennia-open-food-facts-bundle",
  "formatVersion": 1,
  "datasetVersion": "2026-10-24",
  "sourceRevision": "<Hugging Face dataset commit hash>",
  "sourceName": "Open Food Facts",
  "sourceUrl": "https://world.openfoodfacts.org/",
  "licenseName": "Open Database License (ODbL) 1.0",
  "licenseUrl": "https://opendatacommons.org/licenses/odbl/1-0/",
  "attributionText": "Contains information from Open Food Facts, made available under the Open Database License (ODbL) 1.0.",
  "countries": ["au", "us", "gb", "ca", "nz"],
  "perCountryLimit": 10000,
  "productCount": 41234
}
```

`datasetVersion` is the date of the export revision used, in `YYYY-MM-DD` form.

Product line (shown wrapped):

```json
{
  "code": "0818290014313",
  "name": "Greek Yogurt Plain Nonfat",
  "brand": "Chobani",
  "isLiquid": false,
  "servingLabel": "serving",
  "servingSize": 170,
  "packageSize": 907,
  "nutrients": { "energy": 53, "protein": 10, "carbohydrate": 3.6, "fat": 0 },
  "modifiedAt": 1745020800,
  "scans": 412
}
```

*   `nutrients` is compact: each key is a Nutrient id as written in
    `usda_foods.json` (for example `saturated_fat`), and each value is the
    amount per 100 g or ml in that Nutrient's default unit. A Nutrient that Open
    Food Facts does not report is absent, which means *unknown*, never zero
    ([CONTEXT.md](../../CONTEXT.md), "Nutrient"). Readers expand each value to
    the full form the app already stores (`status: complete`, `value`,
    `entered`, `unit`). `entered` is the value formatted by the shared mapping's
    number formatter, so Dart and TypeScript produce the same string.
*   `modifiedAt` is the product's Open Food Facts `last_modified_t`, in Unix
    seconds. It is the "data date" shown to the user, and it decides which copy
    of a product wins (see [One product, one row](#one-product-one-row)).
*   `scans` is the product's `unique_scans_n`, used only to break ranking ties.
*   Products are written with no extra whitespace. The gzip header has a zero
    modification time, so the same input produces the same bytes.

A licence notice sits next to it as
`apps/mobile/assets/seeds/open_food_facts_bundle.LICENSE.md`, and is also
listed in a new root `THIRD_PARTY_DATA.md`.

### Building the bundle

`tools/build-open-food-facts-bundle.mjs` is run by a maintainer, not by CI. Its
input is the Open Food Facts Parquet export on Hugging Face
(`openfoodfacts/product-database`, file `food.parquet`, about 8 GB), pinned to
a dataset commit hash. The Parquet export is a daily conversion of the official
JSONL dump and carries the same product fields under the same licence. The
maintainer downloads the file once and passes its local path; the builder also
accepts the pinned URL.

The builder reads the export with the DuckDB command-line tool, which must be
installed (version recorded in [docs/development.md](../development.md)), and
does this:

1.  Read only the fields it needs: `code`, `product_name`, `generic_name`,
    `brands`, `nutriments`, `serving_quantity`, `serving_quantity_unit`,
    `serving_size`, `product_quantity`, `product_quantity_unit`, `quantity`,
    `countries_tags`, `unique_scans_n`, `last_modified_t`. Where the export
    stores a text field as a list of `{lang, text}` entries, take the entry
    whose `lang` is `main`, else `en`, else the first.
2.  For each launch country tag (`en:australia`, `en:united-states`,
    `en:united-kingdom`, `en:canada`, `en:new-zealand`), keep products that list
    it, have a non-empty name, and report energy (kcal), protein,
    carbohydrate and fat per 100 g. Rank them by `unique_scans_n` descending,
    then `code` ascending, and take the first 10,000.
3.  Merge the five lists and remove duplicate codes.
4.  Map each product with the shared TypeScript mapping
    (`apps/server/src/open-food-facts/product-mapping.ts`, imported through
    `tsx`). Drop any product the mapping excludes.
5.  Write the header and the sorted product lines, gzip them, and print a
    report: products per country before and after merging, products dropped by
    the mapping and why, and the compressed size. The builder exits with an
    error if the compressed file is larger than 6 MB.

The builder is reproducible: the same export revision gives the same file. CI
cannot check this, because the input is 8 GB. CI checks the committed file's
shape instead (see the Verification Plan).

### Bundle size

From a sample of the 100 most-scanned Australian products with complete
nutrition, fetched from the Open Food Facts API on 2026-10-25, a product line
averages 233 bytes before compression and 62 bytes after. About 41,000 products
after merging gives about 2.5 MB. That leaves room inside the 6 MB budget for
longer names in the tail of the list. The builder's size check enforces the
budget.

### Where the bundle is stored

The bundle file is committed to git like the other seeds. A refresh adds about
2.5 MB to the repository history, and refreshes happen at most once a quarter,
with an app release. Git LFS and release-asset downloads were rejected (see
Alternatives Considered).

### The product mapping

The mapping already exists in Dart (`_openFoodFactsRecordFromProduct` in
`training_repositories.dart`). This spec keeps its rules, moves them into the
pure domain layer, adds the TypeScript twin, and adds three rules:

*   **Brand:** the first comma-separated entry of `brands`, trimmed; `null` if
    empty.
*   **Change date:** `last_modified_t` (Unix seconds); a product without it is
    excluded, because the newer-copy rule needs it.
*   **Hard limits:** the mapped nutrient values are checked with the existing
    shared nutrient validator
    (`packages/golden-vectors/vectors/m18-nutrient-validation.json` covers
    it). A product with any hard-reject value (for example energy above the
    validator's ceiling per 100 g) is excluded. A product with only soft
    warnings is kept; the warning appears when it is logged, as today.

The kept rules are unchanged: name from `product_name`, then `product_name_en`,
then `generic_name`; the nutrient key list and unit multipliers (sodium,
cholesterol and caffeine from grams to milligrams); negative values dropped as
unknown; serving and package parsed from the quantity fields; the Food id is
the barcode.

### Installing the bundle on the device

The bundle does not go into the user's database (`AppDatabase`). It goes into a
second Drift database, `FoodReferenceDatabase`, stored as
`food_reference.sqlite` in the app's cache directory. The reasons:

*   It is reference data that can be rebuilt at any time. Keeping it out of the
    user's database keeps it out of sync, backups and the portable archive, and
    keeps the user's database small.
*   Writing 40,000 rows takes seconds. In a separate file, on a background
    isolate, it cannot hold a lock that a Set or Food Entry save waits on
    ([AGENTS.md](../../AGENTS.md), "Local writes never block on the network",
    and the one-frame save rule).
*   If the operating system clears the cache directory, the app rebuilds the
    bundle on the next launch. The only loss is the cache of live-fetched
    products, which can be fetched again.

Its schema:

| Table | Columns |
| :---- | :------ |
| `reference_meta` | `key` text primary key, `value` text. Keys: `bundle_dataset_version`, `bundle_format_version`. |
| `open_food_facts_products` | `code` text primary key; `name` text; `brand` text nullable; `is_liquid` boolean; `serving_label`, `serving_size`, `package_size` nullable; `nutrients_json` text (compact form); `modified_at` integer; `scans` integer nullable; `origin` text, `bundle` or `online`; `last_accessed_at` integer nullable (online rows only). |
| `open_food_facts_products_fts` | FTS5 virtual table over `name` and `brand`, external content `open_food_facts_products`, tokenizer `unicode61 remove_diacritics 2`, kept in step by insert, update and delete triggers. |

`FoodReferenceDatabase` is never migrated. If its schema version changes, the
app deletes the file and builds it again.

On each app start, after the first frame, a background task compares
`reference_meta.bundle_dataset_version` with the asset's header. If they
differ, or the file is new, it installs the bundle in **one transaction**:

1.  Delete every row whose `origin` is `bundle`.
2.  Stream the asset through gzip decompression and insert each product. When
    a row with the same code exists (it can only be an `online` row now), the
    bundle copy replaces it only if its `modified_at` is greater.
3.  Set `bundle_dataset_version` and `bundle_format_version`.

Because it is one transaction, a killed install leaves the old state, and the
next start runs it again (CUJ 8). While it runs, the repository reports the
status `installing`, and the picker shows "Preparing offline food list" above
whatever online-cached matches exist.

The old cache table `open_food_facts_cache` in `AppDatabase` is dropped in
schema version 61. Its rows are not copied: the app has not been released, so
no user holds a cache worth keeping, and Food Entries and the Recent list do not
depend on it.

### One product, one row

The products table has one row per barcode, so the picker cannot show a product
twice. Every write uses the same rule: an incoming copy replaces the stored one
only if its `modified_at` is greater. This applies to bundle installs, live
search results and live barcode lookups. The data date shown is always the
stored row's `modified_at`.

Online rows are capped at 5,000 (the existing
`defaultOpenFoodFactsMaxCacheEntries`). Above that, the online rows with the
oldest `last_accessed_at` are deleted. Bundle rows are never evicted.

### Search and barcode rules

Local search runs as the user types, after the existing 300 ms pause:

*   **Match expression:** lower-case the query, split it on every character
    that is not a Unicode letter or digit, drop empty parts, keep the first 8
    parts, and write each as a quoted prefix term (`"chobani"* "gr"*`). All terms
    must match (FTS5 joins them with AND). A query with no parts searches
    nothing and the list shows "Type a product or brand name".
*   **Order:** `bm25` rank with name weighted 2 and brand weighted 1, then
    `scans` descending (no value counts as 0), then `code` ascending. The limit
    is 50.

Barcode lookup:

*   Remove spaces and hyphens. The result must be 6 to 18 digits (the existing
    rule), or it is not a barcode.
*   Try, in order: the code as given; if it has 12 digits, the code with a
    leading `0` (a UPC-A code as Open Food Facts usually stores it); if it has
    13 digits and starts with `0`, the code without it.
*   A local match is used as it is, with no live refresh. Without a local match,
    and with online lookups on, one live product request is sent for the code as
    given.

### Live requests

All live requests go through a new `OpenFoodFactsClient` in the repository
layer (only repositories touch the network, per
[ARCHITECTURE.md](../../ARCHITECTURE.md)):

| Request | Endpoint | Parameters |
| :------ | :------- | :--------- |
| Search | `GET https://world.openfoodfacts.org/cgi/search.pl` | `search_terms`, `search_simple=1`, `action=process`, `json=1`, `page_size=20`, `page`, `sort_by=unique_scans_n`, `fields` |
| Product | `GET https://world.openfoodfacts.org/api/v3/product/<code>` | `fields` |

*   `fields` is the list from [Building the bundle](#building-the-bundle),
    without `countries_tags` and `unique_scans_n`.
*   **Search endpoint:** full-text search is not in API v2 or v3. `search.pl`
    is the legacy endpoint the Open Food Facts documentation still lists, and
    it has been stable for years. Search-a-licious is the planned replacement,
    but it reports version 0.1.0; moving to it is a Future Improvement.
*   **User-Agent:** `Perennia/<version> (<contact>)`. `<version>` is the app
    version constant (moved out of `PortableArchiveRepository` into a shared
    constant). `<contact>` comes from the build define
    `PRN_OPEN_FOOD_FACTS_CONTACT`, and falls back to
    `https://github.com/perennia-fit/perennia`. Release builds set it to a
    project address.
*   **Request budget:** an in-memory window per request kind: at most 10
    search and 15 product requests in any 60 seconds. A request over the budget
    is not sent; the client returns "rate limited" with the seconds until a slot
    frees. The window resets when the app restarts, which is acceptable because
    a restart takes longer than the limit is meant to protect.
*   **Timeouts and errors:** 10 seconds per request. The client returns one of:
    results, not found (HTTP 404, or v3 `status: failure` with
    `product_not_found`), busy (HTTP 429 or 503), rate limited (local
    budget), offline (no connection or timeout), or malformed (anything that
    does not parse). Nothing is retried automatically.
*   **The setting:** the repository reads the device-level setting
    `onlineFoodLookups` (default on) before every live request, and returns
    "disabled" without sending anything when it is off. It is stored with the
    other device-level settings in the local settings file, so it never syncs:
    one device's choice does not change another's.
*   **What is sent:** only the query or barcode, the User-Agent and an `accept`
    header. No account id, device id or Perennia server address.

### The picker, the scanner and the food detail

With the **Open Food Facts** filter selected:

*   Typing runs the local search. Results appear under **On this device**.
*   Below them, a row **Search Open Food Facts online for "<query>"** (at least
    48 dp tall) appears when the query has a match expression and online
    lookups are on. Tapping it, or the keyboard's search action, sends one live
    search. Results whose barcode is not in the local list appear under **From
    Open Food Facts**, in the order Open Food Facts returned them. **Load more**
    requests the next page. All returned products are written to the products
    table, so a live result that was also a local match updates that row if it
    is newer.
*   Status lines replace the online row when needed: "Preparing offline food
    list", "Online lookups are off", "You're offline", "Open Food Facts is busy.
    Try again in a minute.", and the rate-limit message with its countdown.

The other filters (Recent, User, USDA) are unchanged.

Scanning uses the barcode rules above. The existing "needs network the first
time" banners are replaced by these status lines.

The log-portion screen, which is where a food's facts are shown before and when
it is logged, gains for Open Food Facts foods:

*   the brand, under the name;
*   the existing `FoodSourceBadge` with "ODbL" (already shown);
*   **View on Open Food Facts**, using the existing `AttributionLinkButton`,
    which shows the URL `https://world.openfoodfacts.org/product/<code>` to open
    or copy (no new URL-launching dependency);
*   the disclaimer text from Goal 7;
*   "Open Food Facts data from <date>", from `modified_at`, in the user's locale
    date format.

On the Nutrition Day view, every Food Entry whose snapshot source is Open Food
Facts shows the compact `FoodSourceBadge` (without "ODbL"), as imported entries
already do. The About screen states the disclaimer, the bundle's
`datasetVersion`, its product count and its countries, and says that live
lookups send the search text or barcode to Open Food Facts and can be turned
off under **Settings > Food data**.

`PlatformFoodRecord` and `FoodPickerItem` gain two nullable fields, `brand` and
`sourceModifiedAt`, which are `null` for USDA and User Foods. A Food Entry's
snapshot is unchanged: it keeps the product name, values and source, not the
brand or the date.

### Agent surface

The existing operation `searchAgentPlatformFoods`
(`GET /agent/foods/platform-search`) already has a `source` parameter, limited
to `usda`, reserved for this. This spec widens it rather than adding an
operation.

Request changes:

| Parameter | Change |
| :-------- | :----- |
| `source` | Enum becomes `usda` \| `openFoodFacts`. Default stays `usda`. |
| `barcode` | New, optional. Only with `source=openFoodFacts`. Uses the barcode rules. |
| `online` | New, boolean, default `false`. Only with `source=openFoodFacts`. When true, a search also runs one live search, and a barcode with no bundle match runs one live lookup. |
| `page` | New, integer from 1, default 1. Only with `online=true`; the live search page. |

With `source=openFoodFacts`, exactly one of `search` and `barcode` is required;
otherwise the request fails with HTTP 400. The bundle is too large to list.

Response changes:

*   Each food gains `brand`, `sourceModifiedAt` (ISO-8601) and `productUrl`,
    all `null` for USDA. Whether a product came from the bundle or a live
    lookup is not exposed; `sourceModifiedAt` is what tells an agent how fresh
    it is.
*   `attribution.source` accepts `openFoodFacts`. `attribution` gains
    `disclaimer` (the Goal 7 text for Open Food Facts, `null` for USDA).
    `attribution.datasetVersion` is the bundle header's `datasetVersion`.
*   A new top-level `onlineStatus`: `notRequested`, `ok`, `notFound`, `busy`,
    `rateLimited`, `disabled` or `unavailable`. Bundle results are always
    returned, whatever this says.

On the server, a new module `apps/server/src/open-food-facts/` holds the
TypeScript mapping and normalization, a bundle index, and a live client:

*   **Bundle index:** on the first Open Food Facts request, the server reads the
    bundle file and loads it into an in-memory SQLite database with Node's
    built-in `node:sqlite`, using the same table, FTS5 index, match expression
    and ordering as the app. So for a bundled product, an agent and the app get
    the same record, and for a search over bundle rows, the same order. Node 22,
    the version the repository and the server image use, ships `node:sqlite`
    with FTS5 (checked on 22.21.1). It is marked experimental there; the risk is
    recorded under Non-Functional Requirements.
*   **Finding the file:** the bundle index module resolves
    `../../../mobile/assets/seeds/open_food_facts_bundle.ndjson.gz` relative to
    its own directory (`src/open-food-facts/` or `dist/open-food-facts/`), which
    lands on `apps/mobile/assets/seeds/`. That works in development and in the
    image, because the Dockerfile's runtime stage
    copies the file to the same relative place. The bundle is too large for the
    generated-TypeScript-module approach the USDA seed uses.
*   **Live client:** the same endpoints, fields, timeout and outcomes as the
    app's. The User-Agent is `PerenniaServer/<server package version>
    (<contact>)`. The request budget (10 searches and 15 products per 60
    seconds) is **server-wide**, because Open Food Facts limits by IP address
    and every agent shares the server's. Live results go into the in-memory
    database as `online` rows, capped at 5,000 with the same eviction rule.
*   **Operator settings:** `OPEN_FOOD_FACTS_ONLINE_LOOKUPS` (default `true`;
    `false` makes every `online=true` request return `onlineStatus: disabled`)
    and `OPEN_FOOD_FACTS_CONTACT` (default the repository URL). Both are
    documented in [docs/self-hosting.md](../self-hosting.md).

The MCP tool `agent_search_platform_foods` takes the same input and returns the
same output; only its description and input schema change. The contract diff
shows the widened enum, the four parameters and the new response fields in
`packages/contract/openapi.json`, `agent-client.ts`, the Dart API client and
the agent command map.

Widening an enum in a response is an additive change, but a client that treats
the `source` enum as closed can reject an `openFoodFacts` value. Before 1.0
this is accepted; the contract diff makes it visible in review.

### Invariants

| Invariant ([AGENTS.md](../../AGENTS.md)) | How it holds |
| :--------------------------------------- | :----------- |
| Local writes never block on the network; a save confirms within one frame. | Logging uses the stored row. Live requests happen only on a search submit or a scan miss, before the log-portion screen opens. The bundle installs in a separate database file on a background isolate. |
| Sets and Food Entries are self-describing; templates never rewrite history. | A Food Entry still snapshots values and source at log time. A bundle refresh or a newer live copy changes the products table only. |
| Derived analytics are computed, never stored or synced. | The bundle is reference data, not a derived result. The FTS index is a lookup index that is rebuilt mechanically from its table. |
| Sync is silent last-writer-wins. | `FoodReferenceDatabase` does not sync. Open Food Facts data reaches the server only inside Food Entry snapshots, as today. |
| Validation is one shared two-tier module. | No rule changes. The mapping uses the existing nutrient validator to exclude hard-reject products. Logging runs the validator as today. |
| No behavioral analytics. | Requests carry the query or barcode and a User-Agent naming the app, not the user. The setting turns them off. |
| Restore and import are merge-only; delete is archive. | Not touched. The reference database is not part of backups or the portable archive. |

### Vocabulary

One new [CONTEXT.md](../../CONTEXT.md) term, added in the implementation pull
request:

*   **Platform Food** — a read-only Food whose facts come from an external Food
    Source (USDA or Open Food Facts), either shipped with the app or fetched
    from the source; the food-domain analog of the Platform Library. Customizing
    one forks a User Food. (Code and the agent surface already use this name:
    `PlatformFoodRecord`, `searchAgentPlatformFoods`.)

The Food Source entry also gains one sentence: an Open Food Facts Food can come
from the bundle shipped with the app or from a live lookup, and the copy with
the later Open Food Facts change date is the one used.

### Validation and analytics

*   No validation rule changes, and no tier changes.
*   No analytics computation changes. Nutrition totals keep reading Food Entry
    snapshots.
*   New golden vectors in `packages/golden-vectors/vectors/`:
    *   `m36-open-food-facts-mapping.json` (domain `open-food-facts-mapping`):
        Open Food Facts product objects to the expected compact record or to
        "excluded" with a reason, covering missing names, missing nutrients,
        negative values, unit multipliers, brand parsing, serving and package
        parsing, missing `last_modified_t`, and hard-reject values.
    *   `m36-food-search-normalization.json` (domain
        `food-search-normalization`): queries to match expressions (diacritics,
        punctuation, more than 8 words, quotes and FTS5 operators typed by the
        user) and scanned codes to barcode candidate lists.

## Alternatives Considered

### Alternative A: Live lookups only, no bundle

*   **Pros**: No data pipeline, no repository growth, no ODbL file to manage,
    always the newest values.
*   **Cons**: With no signal, a user finds no branded product they have not
    looked up before. Every new product costs a request against a limit of 10
    searches a minute, and `search.pl` returned HTTP 503 during the research
    for this spec.
*   **Reason for Rejection**: It fails the gym-floor case the app is built
    for, and it depends entirely on a rate-limited service that is sometimes
    unavailable.

### Alternative B: Other ways to choose the bundled products

*   **Worldwide most-scanned list.** Simplest to build, but Open Food Facts
    contributions skew towards France, so it would hold mostly products that
    users in the launch countries never see.
*   **Per-country packs downloaded on first use.** Covers every country, but
    the first offline use needs a download, and the packs need hosting and
    versioning outside the app.
*   **Every country pack built into the app.** Works offline everywhere from
    install, but multiplies the download size.
*   **Reason for Rejection**: The launch-country list gives a predictable size
    and covers the markets the app targets first. Packs remain possible later
    (see Future Improvements).

### Alternative C: Put the bundle in the user's database

*   **Pros**: One database file, one Drift class, joins with Food Entries.
*   **Cons**: 40,000 reference rows would enter the database that syncs, is
    backed up and goes into the portable archive. Installing them takes seconds
    of writes in the same file that Set saves use, which risks the one-frame
    save rule. Every change to the bundle's shape would need an `AppDatabase`
    migration.
*   **Reason for Rejection**: Reference data that can be rebuilt does not
    belong with user-authored data. A separate file costs one extra Drift class
    and removes all three problems.

### Alternative D: Ship a ready-built SQLite file instead of JSON lines

*   **Pros**: No install step on the device; the app opens the file and
    searches.
*   **Cons**: The download would include the FTS index, which is larger than
    the data. A binary file cannot be reviewed in a pull request; JSON lines
    can be inspected with standard tools. On Android, assets are inside the app
    package, so the file would still have to be copied out before SQLite can
    open it.
*   **Reason for Rejection**: Building the index on the device costs a few
    seconds once per bundle version, in the background. That is cheaper than a
    larger download and an unreviewable file.

### Alternative E: Load the bundle into memory, as the USDA seed is loaded

*   **Pros**: Reuses `UsdaFoodSeedSource` and the generated-module pattern on
    the server.
*   **Cons**: 40,000 decoded records with full nutrient objects take tens of
    megabytes of memory on the device, and a linear name match over them is
    slower than an index and ranks nothing. On the server, a generated
    TypeScript module of this size slows type-checking and builds.
*   **Reason for Rejection**: The USDA pattern fits three foods, not 40,000.

### Alternative F: Store the bundle outside plain git

*   **Git LFS.** Keeps history small, but GitHub's free LFS bandwidth runs out
    quickly when CI clones the repository, and every contributor needs LFS
    installed.
*   **A release asset fetched at build time.** Keeps history small, but builds
    then need the network and a hosted file, and the ODbL "keep open" copy
    moves from the repository to a download that can disappear.
*   **Reason for Rejection**: About 2.5 MB a quarter is a small cost for
    builds that work from a plain clone.

### Alternative G: Search-a-licious instead of `search.pl`

*   **Pros**: The planned replacement for full-text search, with a documented
    API (`GET /search` with `q`, `page`, `page_size`, `fields`, `sort_by`).
*   **Cons**: It reports version 0.1.0, publishes no rate limits, and is not
    yet listed by the Open Food Facts API documentation as the supported search
    path.
*   **Reason for Rejection**: `search.pl` is the path the documentation lists
    today. Both are kept behind one client function, so switching later
    changes one file and its tests.

### Alternative H: Route all app lookups through the Perennia server

*   **Pros**: One live client and one cache. The server could hold the only
    copy of the bundle.
*   **Cons**: The app would need an account and a server to look anything up,
    which breaks the rule that the app is complete with no account and no
    network. Every user would share the server's single rate limit.
*   **Reason for Rejection**: It contradicts the offline-first design in
    [ARCHITECTURE.md](../../ARCHITECTURE.md).

### Alternative I: Agents get the bundle only, with no live lookups

*   **Pros**: The agent surface stays deterministic and makes no outbound
    calls, as the existing USDA comment in `agent-foods.ts` prefers.
*   **Cons**: The app can look up any product and an agent could not, which is
    the gap [AGENTS.md](../../AGENTS.md) says the agent surface must not have.
*   **Reason for Rejection**: Live lookups are offered, but only with
    `online=true`, so the default stays deterministic and outbound calls are
    the agent's explicit choice.

### Alternative J: A new agent operation for Open Food Facts

*   **Pros**: A response shape designed only for Open Food Facts, with no
    nullable fields for USDA.
*   **Cons**: Two operations and two MCP tools that do the same thing for two
    sources. The existing operation already reserves the `source` parameter for
    this.
*   **Reason for Rejection**: Widening the existing operation is the change its
    own design anticipated, and it keeps one tool for agents to learn.

### Alternative K: Postgres for the server's bundle search

*   **Pros**: Uses the database the server already runs; no experimental
    Node API.
*   **Cons**: Postgres full-text search tokenizes and ranks differently from
    SQLite FTS5, so an agent and the app would see different results for the
    same query. Loading the bundle needs a schema change and a seeding step on
    every refresh.
*   **Reason for Rejection**: Using the same engine, schema and query on both
    sides is what makes the results match. The experimental-API risk is
    recorded under Non-Functional Requirements.

### Alternative L: The official Open Food Facts Dart SDK

*   **Pros**: Maintained models, User-Agent handling and endpoint coverage.
*   **Cons**: A large dependency for two GET requests. The mapping would still
    need its own Dart and TypeScript code pinned by golden vectors, because the
    server and the bundle builder use TypeScript.
*   **Reason for Rejection**: It saves little code and adds a dependency whose
    models change on its own schedule.

### Alternative M: Pick the winning copy by fetch time

*   **Pros**: No dependency on an Open Food Facts field.
*   **Cons**: A bundle installed after an app update would count as newer than
    a live copy fetched last week, even when the live copy holds a newer
    revision of the product.
*   **Reason for Rejection**: `last_modified_t` records when the product data
    actually changed, so it orders bundle and live copies correctly.

### Alternative N: "Look up foods online" off by default

*   **Pros**: Nothing leaves the device until the user opts in, which is the
    strictest privacy position.
*   **Cons**: Live search and scan misses would fail until the user finds the
    setting, and every live request is already triggered by the user's own
    action (a submit or a scan miss), never in the background.
*   **Reason for Rejection**: Requests happen only on an explicit user action,
    carry no identity, and can be turned off. On by default, with the setting
    named in the About screen, balances use and privacy.

--------------------------------------------------------------------------------

## Non-Functional Requirements

### Security and privacy

*   Live requests send only the search text or barcode, the User-Agent and an
    `accept` header, over HTTPS. No account id, device id, location or Perennia
    server address is sent.
*   Live requests happen only after a user action: submitting an online search,
    tapping **Load more**, or scanning a barcode that is not on the device.
    Nothing is fetched in the background, and installing the bundle sends
    nothing.
*   "Look up foods online" turns all of it off on that device. On the server,
    `OPEN_FOOD_FACTS_ONLINE_LOOKUPS=false` does the same for agents.
*   The bundle and the device cache hold public product data only; no user
    data enters `FoodReferenceDatabase`.

### Performance and storage

*   **Search:** local search returns within 100 ms of the typing pause on a
    mid-range device. CI guards it with a host-side budget over a synthetic
    41,000-row index (see the Verification Plan); device timing is checked by
    hand before release.
*   **Logging:** unchanged. The log-portion screen and the Food Entry save read
    and write only local databases.
*   **Install:** the bundle installs in a background isolate after the first
    frame. Target: under 5 seconds on a mid-range Android device, checked by
    hand before release. Search works during the install against whatever rows
    exist.
*   **Download size:** the bundle adds at most 6 MB compressed; estimated at
    about 2.5 MB. The builder refuses to write a larger file.
*   **Device storage:** the compressed asset (about 2.5 MB) plus
    `food_reference.sqlite` in the cache directory, estimated at 15 to 20 MB
    with the FTS index. The operating system may clear it; the app rebuilds it.
*   **Server memory:** the in-memory bundle index, estimated at 15 to 20 MB,
    loaded on the first Open Food Facts request, not at startup.

### Rollout and rollback

*   The app is unreleased, so there is no staged rollout.
*   Rolling back the app code is a revert. `food_reference.sqlite` is a cache;
    an older build ignores it or deletes it by its schema-version rule.
*   The `AppDatabase` change in version 61 only drops a cache table. A rolled-back
    build that expects version 60 tables cannot open a version 61 database, as
    with any Drift schema bump; on a debug device, reinstall.
*   The agent operation change is additive. Old clients that omit `source` keep
    getting USDA results with the same fields, plus new nullable fields.

### Risks

| Risk | Effect | Mitigation |
| :--- | :----- | :--------- |
| `node:sqlite` is experimental in Node 22. | A Node minor release could change its API and break the server's bundle search. | The server pins Node through `.node-version` and the Docker base image. The bundle index sits behind one module with its own tests, so a change shows up in CI on the Node upgrade pull request. |
| `search.pl` is legacy and sometimes returns 503. | Online search fails some of the time. | Local results stay on screen; the busy message explains the failure; Search-a-licious is a Future Improvement. |
| Open Food Facts bans an IP for heavy use. | Live lookups stop for that device or server. | The request budgets sit below the published limits, nothing retries on its own, and every request identifies Perennia with a contact address. |
| ODbL share-alike for synced Food Entry snapshots. | Unclear obligation for the hosted server. | A lawyer's check before public release (a Non-Goal of this spec). The code that derives the snapshots is public. |

--------------------------------------------------------------------------------

### Additional Resources

*   Open Food Facts API documentation:
    https://openfoodfacts.github.io/openfoodfacts-server/api/ (rate limits,
    User-Agent rule, staging host, read 2026-10-25).
*   Open Food Facts terms of use: https://world.openfoodfacts.org/terms-of-use
    (licences, attribution, accuracy disclaimer).
*   ODbL 1.0 summary and full text:
    https://opendatacommons.org/licenses/odbl/summary/ and
    https://opendatacommons.org/licenses/odbl/1-0/.
*   Open Food Facts Parquet export:
    https://huggingface.co/datasets/openfoodfacts/product-database.
*   Search-a-licious API: https://search.openfoodfacts.org/docs.

### Future Improvements

*   **Search-a-licious.** Move live search to it once Open Food Facts lists it
    as the supported search API. One client function changes.
*   **Country-aware live search.** Filter or rank live results by the device's
    region, once the right parameters are confirmed against a working endpoint.
*   **Country packs** for regions outside the launch list, downloaded once on
    Wi-Fi.
*   **More USDA foods,** so generic foods are found offline too. Needs its own
    spec for the USDA data pipeline.
*   **Brand in the Food Entry snapshot,** so logged history shows "Chobani Greek
    Yogurt" rather than "Greek Yogurt". Changes the Food Entry shape and sync.
*   **A scheduled bundle refresh** in CI, if refreshes become frequent enough to
    justify caching the 8 GB export on a runner.

--------------------------------------------------------------------------------

## Detailed Implementation Plan

The work lands in three implementation pull requests, in this order, each
green on `pnpm ci:local --changed` on its own. Each links this spec.

1.  **Shared rules and the bundle:** the TypeScript and Dart mapping and
    normalization, their golden vectors, the builder, the bundle file, the shape
    check and the licence files.
2.  **The app:** the reference database, the client, the repository, the
    picker, the scanner, the food detail, the setting, and the `AppDatabase`
    change.
3.  **The server:** the bundle index, the live client, the widened agent
    operation and MCP tool, the contract regeneration and the Dockerfile.

The CONTEXT.md change lands in pull request 2, the first one with user-visible
behavior. This spec's Status becomes **Current** in pull request 3.

### Target Files to Create/Modify

#### Pull request 1: shared rules and the bundle

##### 1. `apps/server/src/open-food-facts/product-mapping.ts` (Create)

*   **Type / Scope**: TypeScript module, pure functions. Written with
    erasable-only TypeScript syntax (no `enum`, no parameter properties) so
    the bundle builder can import it through `tsx`.
*   **Proposed Changes**:
    *   `mapOpenFoodFactsProduct(product: Record<string, unknown>, options?: { fallbackCode?: string }): MappedProduct | ExcludedProduct`.
    *   `MappedProduct = { kind: "mapped", code, name, brand, isLiquid, servingLabel, servingSize, packageSize, nutrients: Record<NutrientWireId, number>, modifiedAt }`.
    *   `ExcludedProduct = { kind: "excluded", reason: "missingCode" | "missingName" | "missingModifiedAt" | "hardReject" }`.
    *   Rules exactly as in [The product mapping](#the-product-mapping). The
        hard-reject check calls the existing `validateAgentFoodEntry` in
        `apps/server/src/agent-validation.ts` and excludes the product when it
        returns any error.
    *   `formatOpenFoodFactsNumber(value: number): string`, the same
        formatting as the Dart `_formatOpenFoodFactsNumber`, used to build
        `entered`.
    *   `expandCompactNutrients(nutrients): AgentFoodReadNutrientVector`, which
        turns compact values into the full form.
    *   `OPEN_FOOD_FACTS_FIELDS`: the `fields` list used by live requests and
        the builder.

##### 2. `apps/server/src/open-food-facts/search-normalization.ts` (Create)

*   **Type / Scope**: TypeScript module, pure functions, erasable-only syntax.
*   **Proposed Changes**:
    *   `buildFoodSearchMatch(query: string): string | null`, the match rule in
        [Search and barcode rules](#search-and-barcode-rules). Each term is
        wrapped in double quotes with any double quote inside it doubled, so
        typed FTS5 operators (`AND`, `NEAR`, `*`, `:`) are searched as text.
    *   `barcodeCandidates(raw: string): string[]`, empty when the input is not
        a barcode.

##### 3. `apps/mobile/lib/domain/nutrition/open_food_facts.dart` (Create)

*   **Type / Scope**: Dart domain module, pure (no I/O).
*   **Proposed Changes**: The Dart twins of files 1 and 2:
    `mapOpenFoodFactsProduct`, `OpenFoodFactsMappingResult` (mapped or excluded
    with the same four reasons), `formatOpenFoodFactsNumber`,
    `expandCompactNutrients`, `buildFoodSearchMatch`, `barcodeCandidates`,
    `openFoodFactsFields`, `openFoodFactsProductUrl(code)` (returns
    `https://world.openfoodfacts.org/product/<code>`), and
    `openFoodFactsDisclaimer` (the Goal 7 text). The mapping code moves here
    from `training_repositories.dart` (the `_openFoodFacts*` helpers from
    line 14463 on) and gains the brand, change-date and hard-reject rules. The
    hard-reject check calls the existing `validateFoodEntryNutrition` in
    `lib/domain/training/set_validation.dart` and excludes the product when it
    returns any error.

##### 4. `packages/golden-vectors/vectors/m36-open-food-facts-mapping.json` (Create)

*   **Type / Scope**: Golden vector fixture, `domain: "open-food-facts-mapping"`.
*   **Proposed Changes**: Cases of `{ name, input: <product object>, expected: <MappedProduct or ExcludedProduct> }`.
    At least: a full product; a product with only the four core nutrients;
    `energy-kcal_value` used when `energy-kcal_100g` is absent; a negative
    value dropped as unknown; sodium, cholesterol and caffeine converted to
    milligrams; `product_name` absent with `product_name_en` present; no name
    at all (excluded); no `last_modified_t` (excluded); energy above the
    validator ceiling (excluded, `hardReject`); `brands` with several entries;
    serving and package given as numbers with units, and only as text;
    a liquid product (ml); numbers whose `entered` formatting needs rounding.

##### 5. `packages/golden-vectors/vectors/m36-food-search-normalization.json` (Create)

*   **Type / Scope**: Golden vector fixture, `domain: "food-search-normalization"`.
*   **Proposed Changes**: `matchCases` of `{ query, expected: string | null }`
    covering mixed case, diacritics (left to the tokenizer, so kept), punctuation,
    more than 8 words, a typed double quote, typed `AND`/`NEAR`/`*`, and empty
    or punctuation-only queries. `barcodeCases` of `{ input, expected: string[] }`
    covering 8, 12 and 13 digits, a 13-digit code starting with `0`, spaces and
    hyphens, letters, and 5 and 19 digits.

##### 6. `packages/golden-vectors/vectors/README.md` (Modify)

*   **Type / Scope**: Documentation.
*   **Proposed Changes**: A section naming both new fixtures, their domains,
    and the two runners that execute them.

##### 7. `apps/server/test/open-food-facts.golden.test.mjs` (Create)

*   **Type / Scope**: Node test.
*   **Proposed Changes**: Loads every fixture with the two new domains, runs
    the TypeScript functions, asserts each case, and asserts that at least one
    case of each domain ran (the same guard pattern as
    `nutrition-analytics.golden.test.mjs`).

##### 8. `apps/server/package.json` and `apps/server/test/agent-validation.golden.test.mjs` (Modify)

*   **Type / Scope**: Build configuration and the TypeScript domain guard.
*   **Proposed Changes**: Add `test/open-food-facts.golden.test.mjs` to the
    `test:golden-vectors` script. Add `open-food-facts-mapping` and
    `food-search-normalization` to `DOMAINS_OWNED_ELSEWHERE` in
    `agent-validation.golden.test.mjs`, each with a comment naming
    `open-food-facts.golden.test.mjs` as its runner. Without this, that test's
    guard fails on the new fixtures, because every vector domain must be owned
    by exactly one TypeScript runner.

##### 9. `apps/mobile/test/domain/open_food_facts_golden_test.dart` (Create) and `apps/mobile/test/domain/golden_vector_ownership_test.dart` (Modify)

*   **Type / Scope**: Dart unit test and the Dart domain guard.
*   **Proposed Changes**: The Dart runner for the same fixtures, with the same
    at-least-one-case guard. It reads the fixtures from
    `packages/golden-vectors`, which is what the CI golden job's discovery step
    looks for. In `golden_vector_ownership_test.dart`, map both new domains to
    `test/domain/open_food_facts_golden_test.dart`; that test fails on any
    domain with no Dart runner.

##### 10. `tools/build-open-food-facts-bundle.mjs` (Create)

*   **Type / Scope**: Maintainer tool, Node ESM.
*   **Proposed Changes**: Usage:
    `node --import tsx tools/build-open-food-facts-bundle.mjs --input <path-or-url> --revision <dataset commit hash> --dataset-version <YYYY-MM-DD>`.
    It runs the steps in [Building the bundle](#building-the-bundle): it shells
    out to `duckdb` with a SQL query that selects the fields, filters and ranks
    per country tag, and writes the candidate rows as JSON lines to a temporary
    file; then it maps each row with file 1, sorts by code, writes the header
    and lines, gzips with a zero modification time, writes
    `apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz`, and prints the
    report. It exits non-zero if `duckdb` is missing, if a required field is
    missing from the export, or if the result is over 6 MB. Constants at the top:
    the five country tags, the per-country limit (10,000), and the size budget.

    A second mode, `node tools/build-open-food-facts-bundle.mjs --verify <file>`,
    is the CI shape check. It needs neither DuckDB nor `tsx`: the builder
    imports the TypeScript mapping with a dynamic `import()` only in build mode.
    It reads the committed bundle and fails if: the header's `format` or
    `formatVersion` is not the expected value; `productCount` does not equal the
    number of product lines; codes are not unique or not sorted; any line is
    missing a required key or has a nutrient key that is not a Nutrient id; the
    gzip header modification time is not zero; or the file is over 6 MB. The
    header and line format are defined once in this file and used by both
    modes.

##### 11. `apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz` (Create)

*   **Type / Scope**: Generated data, ODbL.
*   **Proposed Changes**: Output of file 10 against the export revision current
    when pull request 1 is opened. The pull request description records the
    revision hash and the builder's report.

##### 12. `apps/mobile/assets/seeds/open_food_facts_bundle.LICENSE.md` (Create)

*   **Type / Scope**: Licence notice.
*   **Proposed Changes**: States that the bundle is a derived database of Open
    Food Facts, made available under ODbL 1.0, with individual contents under
    DbCL 1.0; names the source revision; links openfoodfacts.org, both
    licences, and `tools/build-open-food-facts-bundle.mjs` as the method used
    to derive it; and repeats the accuracy disclaimer.

##### 13. `THIRD_PARTY_DATA.md` (Create)

*   **Type / Scope**: Repository-root notice.
*   **Proposed Changes**: One table: each bundled dataset (Open Food Facts
    bundle, USDA FoodData Central seed, platform exercises), its file, its
    licence, the attribution required, and its licence file. States that the
    data licences are separate from the AGPL-3.0 code licence.

##### 14. `.github/workflows/ci.yml` and `tools/ci-local.mjs` (Modify)

*   **Type / Scope**: CI configuration, changed together.
*   **Proposed Changes**:
    *   `golden` job: add `apps/server/src/open-food-facts/**` and
        `apps/server/test/open-food-facts.golden.test.mjs` to its paths. The
        Dart side needs no change: the job's paths already cover
        `apps/mobile/lib/domain/**` and `apps/mobile/test/domain/**`, and its
        Dart step runs every test that reads `packages/golden-vectors`.
    *   `contract` job: add the bundle file and
        `tools/build-open-food-facts-bundle.mjs` to its paths, and run
        `node tools/build-open-food-facts-bundle.mjs --verify apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz`
        before the drift check.

##### 15. `docs/development.md` (Modify)

*   **Type / Scope**: Documentation.
*   **Proposed Changes**: A section "Refreshing the Open Food Facts bundle": the
    required DuckDB CLI version, downloading the pinned export, the builder
    command, reading the report, and the rule that a refresh happens at most once
    a quarter, in its own pull request, with the revision in the description.

#### Pull request 2: the app

##### 16. `apps/mobile/lib/data/local/food_reference_database.dart` (Create)

*   **Type / Scope**: Drift database (Dart tables, generated code).
*   **Proposed Changes**:
    *   `FoodReferenceDatabase` with tables `ReferenceMeta` and
        `OpenFoodFactsProducts` (columns in
        [Installing the bundle on the device](#installing-the-bundle-on-the-device)),
        `schemaVersion = 1`.
    *   `onCreate` creates the FTS5 table and its three triggers with
        `customStatement`. There is no `onUpgrade`; the opener deletes the file
        when the stored `user_version` differs from `schemaVersion`.
    *   Factories: `FoodReferenceDatabase.memory()` for tests and
        `FoodReferenceDatabase.openDefault()`, which opens
        `food_reference.sqlite` in `getApplicationCacheDirectory()` with
        `NativeDatabase.createInBackground`.
    *   Queries: `searchProducts(match, limit)` (the FTS join and order from
        [Search and barcode rules](#search-and-barcode-rules)),
        `productsByCodes(codes)`, `upsertIfNewer(rows, origin)` (the
        [One product, one row](#one-product-one-row) rule, as
        `INSERT ... ON CONFLICT(code) DO UPDATE ... WHERE excluded.modified_at > modified_at`),
        `touch(code, at)`, `evictOnlineRows(max)`, `metaValue(key)`,
        `setMeta(key, value)`, and `replaceBundle(Stream<rows>, header)`, which
        runs the three install steps in one transaction.
    *   `foodReferenceDatabaseProvider` (Riverpod), closed on dispose.

##### 17. `apps/mobile/lib/data/local/food_reference_database.g.dart` (Create, generated)

*   **Type / Scope**: Generated by `build_runner`.
*   **Proposed Changes**: Committed, like `app_database.g.dart`.

##### 18. `apps/mobile/lib/data/open_food_facts/open_food_facts_bundle_installer.dart` (Create)

*   **Type / Scope**: Repository-layer service.
*   **Proposed Changes**: `OpenFoodFactsBundleInstaller` with
    `Future<void> ensureInstalled()` and `Stream<BundleStatus> status`
    (`unknown`, `installing`, `ready`, `failed`). It reads the asset through an
    injectable `BundleAssetSource` (the default uses `rootBundle`), reads the
    header, compares `datasetVersion` with `reference_meta`, and when they
    differ streams the lines through `gzip` decoding into
    `FoodReferenceDatabase.replaceBundle`. A failure sets `failed` and is
    reported to the opt-in crash reporter only; the next app start tries again.
    `bundleInfo()` returns the header for the About screen.

##### 19. `apps/mobile/lib/data/open_food_facts/open_food_facts_client.dart` (Create)

*   **Type / Scope**: Repository-layer HTTP client.
*   **Proposed Changes**:
    *   `OpenFoodFactsClient({required http.Client httpClient, required Uri baseUrl, required String userAgent, DateTime Function()? clock})`.
    *   `Future<OpenFoodFactsSearchOutcome> search(String query, {required int page})`
        and `Future<OpenFoodFactsProductOutcome> product(String code)`, with
        the endpoints, parameters, 10-second timeout and outcomes from
        [Live requests](#live-requests). Products in a response are mapped
        with `mapOpenFoodFactsProduct`; excluded products are left out.
    *   `RequestBudget` (in the same file): a sliding 60-second window with a
        capacity, `tryAcquire()` returning either granted or the seconds to wait.
        One budget for search (10) and one for products (15).
    *   `perenniaUserAgent()`: `Perennia/$appVersion ($contact)`, with
        `contact` from `String.fromEnvironment('PRN_OPEN_FOOD_FACTS_CONTACT')`,
        falling back to `https://github.com/perennia-fit/perennia`.

##### 20. `apps/mobile/lib/data/app_version.dart` (Create)

*   **Type / Scope**: Shared constant.
*   **Proposed Changes**: `const appVersion = '0.1.0+1';`, the value moved from
    `PortableArchiveRepository.appVersion`. The User-Agent uses the part before
    `+`.

##### 21. `apps/mobile/lib/data/repositories/portable_archive_repository.dart` (Modify)

*   **Type / Scope**: Repository.
*   **Proposed Changes**: `PortableArchiveRepository.appVersion` refers to the
    shared constant instead of declaring its own value, so existing callers
    are unchanged.

##### 22. `apps/mobile/lib/data/repositories/open_food_facts_repository.dart` (Create)

*   **Type / Scope**: Repository.
*   **Proposed Changes**: `OpenFoodFactsRepository`, moved out of
    `training_repositories.dart` and rewritten:
    *   `Future<void> ensureBundleInstalled()` and
        `Stream<BundleStatus> get bundleStatus`, both delegating to the
        installer, and `Future<BundleHeader?> bundleInfo()` for the About
        screen.
    *   `Future<List<PlatformFoodRecord>> searchLocal(String query, {int limit = 50})`.
    *   `Future<OnlineSearchResult> searchOnline(String query, {required int page, required bool allowOnline})`:
        returns `disabled` without sending when `allowOnline` is false;
        otherwise calls the client, writes returned products with
        `upsertIfNewer(..., origin: online)`, evicts above
        `defaultOpenFoodFactsMaxCacheEntries`, and returns the products (as
        stored after the upsert) with the outcome.
    *   `Future<BarcodeLookupResult> lookupBarcode(String raw, {required bool allowOnline})`:
        the barcode rules; on a local hit, touches the row and returns it; on a
        miss, a live product request when allowed.
    *   Records returned are `PlatformFoodRecord` with `brand` and
        `sourceModifiedAt` set, built with `expandCompactNutrients`.

##### 23. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

*   **Type / Scope**: Repository aggregate.
*   **Proposed Changes**: Remove the old `OpenFoodFactsRepository` class and the
    `_openFoodFacts*` helpers (moved to files 3 and 22). `TrainingRepositories`
    keeps its `openFoodFacts` field and its existing constructor parameters
    (`openFoodFactsBaseUrl`, `openFoodFactsHttpClient`,
    `openFoodFactsMaxCacheEntries`, `openFoodFactsClock`), and gains
    `FoodReferenceDatabase? foodReferenceDatabase` and
    `BundleAssetSource? openFoodFactsBundleSource`. When omitted, it uses
    `FoodReferenceDatabase.openDefault()` and the `rootBundle` source.

##### 24. `apps/mobile/lib/data/local/app_database.dart` (Modify)

*   **Type / Scope**: Drift schema.
*   **Proposed Changes**: Delete the `OpenFoodFactsCache` table class, remove it
    from the `@DriftDatabase` table list, delete the `openFoodFactsCacheTable`
    name constant and its entry in `schemaTableNames` (around line 1296), set `schemaVersion` to 61, and
    add `if (from < 61) { await customStatement('DROP TABLE IF EXISTS open_food_facts_cache'); }`.
    The `from < 33` step that creates the table is removed, since a database
    upgraded from below 33 now skips straight past it. A docstring on the
    version-61 step states why no rows are copied.

##### 25. `apps/mobile/lib/data/local/app_database.g.dart` (Modify, generated)

*   **Type / Scope**: Generated by `build_runner`.
*   **Proposed Changes**: Regenerated.

##### 26. `apps/mobile/lib/domain/nutrition/nutrition.dart` (Modify)

*   **Type / Scope**: Domain model.
*   **Proposed Changes**: `PlatformFoodRecord` gains `final String? brand` and
    `final DateTime? sourceModifiedAt`, both optional and `null` by default.

##### 27. `apps/mobile/lib/features/nutrition/repositories/add_food_repository.dart` (Modify)

*   **Type / Scope**: Feature repository.
*   **Proposed Changes**:
    *   `FoodPickerItem` gains `brand` and `sourceModifiedAt`.
    *   The `openFoodFacts` filter's `search` calls `searchLocal`.
    *   New `searchOnline(query, page)` and `lookupBarcode(code)` that read the
        `onlineFoodLookups` setting and pass it as `allowOnline`. The provider
        passes a `Future<bool> Function()` that reads
        `settingsControllerProvider`, so the repository holds no widget state.

##### 28. `apps/mobile/lib/features/nutrition/controllers/add_food_controller.dart` (Modify)

*   **Type / Scope**: Riverpod controller.
*   **Proposed Changes**:
    *   `submitQuery` in the Open Food Facts filter calls `searchOnline` for
        page 1. In other filters it is unchanged.
    *   New `loadMoreOnline()` for the next page.
    *   `AddFoodPickerState` gains `localResults`, `onlineResults` (barcodes
        already in `localResults` removed), `onlinePage`, `onlineHasMore`
        (true when the last page returned 20 products), `onlineStatus`
        (`idle`, `loading`, `ok`, `notFound`, `busy`, `rateLimited(seconds)`,
        `offline`, `disabled`, `malformed`) and `bundleStatus`.
    *   `setQuery` keeps the 300 ms local search and clears online results when
        the query changes.
    *   `lookupBarcode` calls the repository's `lookupBarcode`; the existing
        `BarcodeLookupStatus` values are kept, with `rateLimited`, `busy` and
        `disabled` added.
    *   The old `brandedSearchNeedsNetwork` flag is removed.

##### 29. `apps/mobile/lib/features/nutrition/widgets/add_food_picker.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**: The section headings, the online search row, **Load
    more**, and the status lines from
    [The picker, the scanner and the food detail](#the-picker-the-scanner-and-the-food-detail),
    each with a `Key` constant on `AddFoodPicker`. Result rows show the brand
    as a secondary line. All new controls are at least
    `AppDimens.touchTarget` tall. Text uses `context.textStyles` and colours
    from `context.colors`; no new tokens. The two "needs network the first
    time" messages are removed.

##### 30. `apps/mobile/lib/features/nutrition/widgets/nutrition_attribution.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**: Add `OpenFoodFactsProductAttribution`, a widget that
    takes a code and a change date and shows the **View on Open Food Facts**
    `AttributionLinkButton`, the disclaimer, and "Open Food Facts data from
    <date>" (formatted with `DateFormat.yMMMd` in the current locale). Add its
    keys to `NutritionAttributionKeys`.

##### 31. `apps/mobile/lib/features/nutrition/widgets/log_portion_screen.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**: Under the name, the brand when present. Below the
    badge row, `OpenFoodFactsProductAttribution` when the food's source is
    Open Food Facts and it has a `sourceModifiedAt`.

##### 32. `apps/mobile/lib/features/nutrition/widgets/nutrition_day_view.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**: Show the compact `FoodSourceBadge` on a Food Entry row
    when its source is `openFoodFacts`, in the same slot imported entries use
    (around line 1122).

##### 33. `apps/mobile/lib/features/settings/repositories/settings_repository.dart` (Modify)

*   **Type / Scope**: Settings model.
*   **Proposed Changes**: `AppSettings` gains `onlineFoodLookups` (default
    `true`), read and written in `fromJson`/`toJson` and `copyWith`, and kept in
    the device-level half by `SplitSettingsRepository` (never written to the
    synced account row).

##### 34. `apps/mobile/lib/features/settings/widgets/settings_screen.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**: A "Food data" section with one switch, "Look up foods
    online", and the subtitle "Sends your search or barcode to Open Food Facts.
    The offline list works without it."

##### 35. `apps/mobile/lib/features/settings/widgets/about_screen.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**: Replace the Open Food Facts paragraph (around line
    101) with the bundle text from the Technical Plan: dataset version, product
    count, countries, the disclaimer, and what live lookups send. Replace the
    offline paragraph (around line 145) so it no longer says Open Food Facts
    needs the network once.

##### 36. `apps/mobile/lib/app.dart` (Modify)

*   **Type / Scope**: App shell.
*   **Proposed Changes**: In the existing first-frame callback (around line
    140), call `unawaited(ref.read(trainingRepositoriesProvider).openFoodFacts.ensureBundleInstalled())`.

##### 37. `apps/mobile/pubspec.yaml` (Modify)

*   **Type / Scope**: Build configuration.
*   **Proposed Changes**: Add `assets/seeds/open_food_facts_bundle.ndjson.gz`
    and `assets/seeds/open_food_facts_bundle.LICENSE.md` to `flutter.assets`.

##### 38. `.github/workflows/ci.yml` and `tools/ci-local.mjs` (Modify)

*   **Type / Scope**: CI configuration, changed together.
*   **Proposed Changes**: In the `mobile` job, extend the generated-code diff
    check to `apps/mobile/lib/data/local/food_reference_database.g.dart`.

##### 39. `CONTEXT.md` (Modify)

*   **Type / Scope**: Vocabulary.
*   **Proposed Changes**: Add **Platform Food** and the Food Source sentence
    from [Vocabulary](#vocabulary).

##### 40. `ARCHITECTURE.md` (Modify)

*   **Type / Scope**: Documentation.
*   **Proposed Changes**: In "The app", one paragraph: reference data that can
    be rebuilt (the Open Food Facts bundle and its live cache) lives in a
    separate database file in the cache directory, outside sync and backups.

##### 41. App tests (Create and Modify)

*   **Type / Scope**: Tests, all against real in-memory SQLite.
*   **Proposed Changes**:
    *   `test/data/food_reference_database_test.dart` (Create): FTS5 is
        available; the match and order rules; `upsertIfNewer` keeps the newer
        copy in both directions; a bundle install keeps a newer online row and
        replaces an older one; deleting stale bundle rows on reinstall;
        eviction keeps bundle rows; a failure inside `replaceBundle` leaves the
        previous state (the kill-mid-install case, CUJ 8).
    *   `test/data/open_food_facts_client_test.dart` (Create), with
        `MockClient`: the exact User-Agent, URLs and parameters; v3 found and
        not-found bodies; 404, 429, 503, timeout and malformed outcomes; the
        11th search and 16th product request in 60 seconds are not sent.
    *   `test/data/open_food_facts_bundle_installer_test.dart` (Create): installs
        from a small fixture bundle, skips when the version matches, reinstalls
        when it differs, reports `failed` on a corrupt file.
    *   `test/features/nutrition/add_food_repository_test.dart` (Modify): local
        search for the Open Food Facts filter; online search and barcode lookup
        send nothing when `onlineFoodLookups` is off.
    *   `test/features/nutrition/add_food_picker_test.dart` (Modify): no request
        while typing; the online row and the keyboard action each send one;
        sections with no duplicate barcode; **Load more**; every status line;
        `meetsGuideline` for tap target size and text contrast on the new
        controls.
    *   `test/features/nutrition/log_portion_screen_test.dart` (Modify): brand,
        product link, disclaimer and date for an Open Food Facts food; none of
        them for USDA.
    *   `test/features/nutrition/nutrition_day_view_test.dart` (Modify): the
        badge on Open Food Facts entries.
    *   `test/features/settings/settings_screen_test.dart` (Modify): the switch,
        its persistence in the device file, and that it is absent from the
        synced account row.
    *   `test/data/` migration test for version 61 (Create,
        `open_food_facts_cache_drop_migration_test.dart`): a version-60 database
        with rows in `open_food_facts_cache` opens at 61 without the table and
        with every other table intact.
    *   `test/performance/performance_budgets_test.dart` and
        `performance_budget_thresholds.dart` (Modify): a 41,000-row synthetic
        index; a two-word prefix search completes under
        `openFoodFactsLocalSearchBudget` (100 ms). `test/performance/README.md`
        gains its row.
    *   Existing tests that used `open_food_facts_cache` or the old
        `search`/`lookup` methods
        (`nutrition_repository_test.dart`, `sync_repository_test.dart`) are
        updated to the new repository.

#### Pull request 3: the server

##### 42. `apps/server/src/open-food-facts/bundle-index.ts` (Create)

*   **Type / Scope**: TypeScript module.
*   **Proposed Changes**: `OpenFoodFactsBundleIndex` with
    `static async load(path: string): Promise<OpenFoodFactsBundleIndex>`, which
    creates a `node:sqlite` `DatabaseSync(':memory:')` with the same table,
    FTS5 table and triggers as file 16 and inserts the bundle in one
    transaction. Methods: `header`, `search(query, limit)` (using
    `buildFoodSearchMatch` and the same `ORDER BY`), `byCodes(codes)`,
    `upsertIfNewer(rows, origin)`, `evictOnlineRows(max)`. A module-level
    `getOpenFoodFactsBundleIndex()` loads it once, on first call, from
    `new URL("../../../mobile/assets/seeds/open_food_facts_bundle.ndjson.gz", import.meta.url)`
    (from `src/open-food-facts/` and `dist/open-food-facts/` alike).

##### 43. `apps/server/src/open-food-facts/client.ts` (Create)

*   **Type / Scope**: TypeScript module.
*   **Proposed Changes**: The server twin of file 19: same endpoints, `fields`,
    timeout and outcomes, using `fetch` with `AbortSignal.timeout(10_000)`. A
    module-level server-wide `RequestBudget` (10 searches, 15 products per 60
    seconds). User-Agent `PerenniaServer/<version from apps/server/package.json> (<contact>)`.

##### 44. `apps/server/src/agent-foods.ts` (Modify)

*   **Type / Scope**: Agent route definitions and handler logic.
*   **Proposed Changes**:
    *   `AgentPlatformFoodSourceSchema` becomes `z.enum(["usda", "openFoodFacts"])`.
    *   `AgentPlatformFoodSchema` gains `brand`, `sourceModifiedAt`,
        `productUrl`; `AgentPlatformFoodAttributionSchema` gains
        `disclaimer`; `AgentFoodPlatformSearchResponseSchema` gains
        `onlineStatus`.
    *   `AgentFoodPlatformSearchQuerySchema` gains `barcode`, `online` and
        `page`. The cross-field rules in [Agent surface](#agent-surface) are
        checked in the handler, which returns HTTP 400 with a new
        `AgentPlatformFoodSearchInvalidRequestResponseSchema`
        (`{ code: "agent_platform_food_search_invalid_request", message }`),
        following the pattern of `agent_effect_window_invalid_request` in
        `app.ts`. The route's `responses` gain the `400` entry.
    *   `searchAgentPlatformFoods` becomes `async` and takes
        `{ search, barcode, source, online, page, limit }` plus an injected
        `{ bundleIndex, client, onlineLookupsEnabled }`. The USDA branch is
        unchanged except for the new nullable fields. The route and handler
        descriptions drop "not available in this slice". The comment block
        above the platform search (around line 216) is rewritten to describe
        the bundle and the `online` opt-in.

##### 45. `apps/server/src/app.ts` and `apps/server/src/index.ts` (Modify)

*   **Type / Scope**: Server wiring.
*   **Proposed Changes**: `index.ts` reads `OPEN_FOOD_FACTS_ONLINE_LOOKUPS`
    (anything but `false` is on) and `OPEN_FOOD_FACTS_CONTACT`, builds the
    client, and passes both into the app factory. The handler in `app.ts`
    (around line 2665) awaits the new function.

##### 46. `apps/server/src/agent-mcp.ts` (Modify)

*   **Type / Scope**: MCP tool.
*   **Proposed Changes**: `agent_search_platform_foods` passes the new query
    fields through and awaits the result. Its description says the tool covers
    USDA and Open Food Facts, the bundle by default, and live lookups with
    `online: true`. `AgentMcpFoodPlatformSearchInputSchema` follows the query
    schema.

##### 47. Server tests (Create and Modify)

*   **Type / Scope**: Node tests.
*   **Proposed Changes**:
    *   `apps/server/test/open-food-facts-bundle-index.test.mjs` (Create):
        loads a small fixture bundle; search order matches the Dart test's
        expected order for the same fixture and query; barcode candidates;
        newer-copy rule; eviction.
    *   `apps/server/test/open-food-facts-client.test.mjs` (Create): with a
        stubbed `fetch`: User-Agent, URLs, outcomes, the server-wide budget.
    *   The existing agent-foods route test (Modify): `source` defaults to
        USDA with unchanged results; `source=openFoodFacts` with `search`, with
        `barcode`, with neither (400), with `online=true` while disabled
        (`onlineStatus: disabled`); the MCP tool returns the same body as REST
        for the same input.

##### 48. `Dockerfile` (Modify)

*   **Type / Scope**: Container build.
*   **Proposed Changes**: In the `runtime` stage, `COPY apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz ./apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz`.

##### 49. `docs/self-hosting.md` (Modify)

*   **Type / Scope**: Documentation.
*   **Proposed Changes**: Add `OPEN_FOOD_FACTS_ONLINE_LOOKUPS` and
    `OPEN_FOOD_FACTS_CONTACT` to the Optional table, with a note that live
    lookups share one Open Food Facts rate limit per server IP address.

##### 50. Generated contract files (Modify, generated)

*   **Type / Scope**: Generated by `corepack pnpm --filter @perennia/contract generate`.
*   **Proposed Changes**: `packages/contract/openapi.json`,
    `packages/contract/src/agent-client.ts`,
    `apps/mobile/lib/api/perennia_api_client.dart`, and the generated table in
    `agent-skills/perennia/references/api-operations.md`.

##### 51. `agent-skills/perennia/references/api-operations.md` and `agent-skills/perennia/SKILL.md` (Modify)

*   **Type / Scope**: Agent documentation (hand-written parts).
*   **Proposed Changes**: The "Food Library Reads and Writes" prose (around
    line 398) describes `source=openFoodFacts`, `barcode`, `online`, `page`,
    `onlineStatus`, and the attribution and disclaimer to show. `SKILL.md`
    gains an example next to the existing one at line 104:
    `search-platform-foods --query source=openFoodFacts --query barcode=<code>`.

##### 52. `docs/designs/open-food-facts.md` (Modify)

*   **Type / Scope**: This spec.
*   **Proposed Changes**: Status set to **Current**, and its SITEMAP row
    updated to match.

### Verification Plan

*   **Gate:** `pnpm ci:local --changed` green for each pull request. The jobs
    that must run and pass:
    *   pull request 1: `golden` (both runners execute the new fixtures) and
        `contract` (bundle shape check);
    *   pull request 2: `mobile` (codegen diff checks for both databases,
        `flutter analyze`, performance budgets, `flutter test`) and `golden`;
    *   pull request 3: `js`, `contract` (drift check shows the expected
        contract diff and nothing else), `golden`, and `sync` (no change
        expected; it confirms Food Entry snapshots with `openFoodFacts` still
        sync).
*   **Unit and repository tests:** as listed in files 7, 9, 41 and 47. All app
    repository tests run against real in-memory SQLite.
*   **Golden vectors:** the two new fixtures, run by Dart and TypeScript.
*   **Kill and reopen:** the `replaceBundle` failure test (CUJ 8), and the
    existing kill-and-reopen mid-workout scenario, which must stay green with
    the installer running on start.
*   **Accessibility:** `meetsGuideline` checks on the picker's new controls and
    the log-portion attribution block, in both themes.
*   **By hand, before release:**
    *   On a mid-range Android device and an iPhone: install time of the real
        bundle (target under 5 seconds), local search latency (under 100 ms),
        app download size increase (under 6 MB), and CUJs 1 to 5 in flight mode
        and online.
    *   Against the Open Food Facts staging host
        (`https://world.openfoodfacts.net`, basic auth `off`/`off`, set through
        `openFoodFactsBaseUrl`): one search, one found product, one missing
        product.
    *   An agent session running CUJ 6 through REST and through MCP, comparing
        the returned record with the app's for the same barcode.

--------------------------------------------------------------------------------

<!-- Provenance: Indicates initial structural drafting via EGM. -->

*Drafted with EGM*
