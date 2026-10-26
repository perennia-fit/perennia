# Open Food Facts Integration

*   **Author:** Leonardo Pinheiro
*   **Status:** Approved (2026-10-26)
*   **Date:** 2026-10-26 (revised after Goldfish review; first draft 2026-10-25)

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
scanner, a small device cache, a source badge on each food, and an attribution
notice. That integration has defects (listed under The Problem), needs the
network for every new product, and has no equivalent on the agent surface.

This spec does four things:

1.  **Ships an offline bundle** of common products from five launch countries
    (Australia, the United States, the United Kingdom, Canada and New Zealand),
    so that search and barcode lookup work with no signal.
2.  **Fixes live search and lookup in the app** so that they return lists, stay
    within Open Food Facts' published rate limits, identify Perennia, and use
    the current API version.
3.  **Makes the source visible and attributed:** every Open Food Facts food shows
    its source and licence, links to its product page, and carries Open Food
    Facts' own accuracy disclaimer.
4.  **Gives agents the same bundle** through the existing Platform Food search
    operation and its MCP tool. The server makes no calls to Open Food Facts.

Terms used below:

*   **Platform Food** — a read-only Food whose facts come from an external Food
    Source. It is a new CONTEXT.md term, defined under [Vocabulary](#vocabulary);
    the code already uses the name (`PlatformFoodRecord`).
*   **Bundle** — the Open Food Facts products shipped inside the app, described
    under [The bundle file](#the-bundle-file).
*   **Device cache** — the Open Food Facts products the app fetched live and kept
    on the device (see [One product, one row](#one-product-one-row)).
*   **Change date** — the time Open Food Facts last changed a product's data (its
    `last_modified_t`). Not to be confused with the bundle's **dataset version**,
    the date of the Open Food Facts dump the bundle was built from.
*   **FTS5** — SQLite's full-text search extension. **bm25** is its relevance
    ranking function.

### The licence, in short

The Open Food Facts database is published under the Open Database License
(ODbL) 1.0. Individual values are under the Database Contents License (DbCL)
1.0, and product photos under the Creative Commons Attribution-ShareAlike 3.0
licence (CC BY-SA 3.0). ODbL asks for three things:

*   **Attribution.** Name Open Food Facts, name the licence, and link to
    openfoodfacts.org or the product's own page, wherever the data or something
    made from it is shown publicly.
*   **Share-alike.** A modified copy of the database that is used publicly must
    be offered under ODbL too, either the copy itself or the method used to make
    it (ODbL section 4.6). This covers data only; Perennia's code stays
    AGPL-3.0.
*   **Keep open.** A copy distributed in a restricted form (for example inside
    an encrypted app package) must also be available without the restriction,
    in a form at least as accessible in practice (section 4.7).

The bundle is a modified copy (filtered and reshaped) that Perennia
distributes. So it is published under ODbL in the repository, with the tool that
builds it, and the app says where to find both.

## The Problem

A user logging a branded food (a yogurt, a protein bar, a sports drink) today
runs into four failures.

1.  **No signal, no product.** Every Open Food Facts product the user has not
    looked up before needs the network, and gyms and basements often have poor
    signal. The bundled USDA catalogue, the only offline reference data, holds
    three generic foods. An offline user finds nothing but their own User Foods
    and their Recent list.
2.  **Search returns one product.** `OpenFoodFactsRepository.search()` in
    `training_repositories.dart` keeps only the first usable product in the
    response. A search for "greek yogurt" shows a single yogurt, and the user
    cannot choose among the others.
3.  **The app breaks Open Food Facts' usage rules, and risks being blocked.**
    *   The picker searches 300 ms after the user stops typing
        (`AddFoodPickerController.searchDebounceDuration`). With the Open Food
        Facts filter selected, each pause sends a request. Open Food Facts allows
        10 search requests per minute per IP address and names
        search-as-you-type as a way to be blocked.
    *   Requests carry no custom User-Agent. Open Food Facts asks every client
        to identify itself as `AppName/Version (ContactEmail)`.
    *   Barcode lookups use API v2, which Open Food Facts marks deprecated.
    *   Partial queries ("gre", "gree", "greek") each become a cache row,
        because the cache is keyed by query text and holds one product per
        query.
4.  **The source is shown, but not explained.** The badge says "Open Food
    Facts", and the existing `OpenFoodFactsAttributionNotice` links the source
    and the licence. Nothing tells the user that the values are crowdsourced and
    can be wrong, which Open Food Facts itself states: its data is indicative,
    not guaranteed accurate or complete, and "must not be used for medical
    purposes". There is no link to the product's own page to check or correct
    it.

The current mapping has two data-quality defects as well:

*   When `energy-kcal_100g` is missing it falls back to `energy-kcal_value`,
    which is on the label's basis. That basis is often per serving, so the
    fallback can store per-serving energy as per-100 g energy.
*   It has no sanity check per 100 g. A product with kilojoules entered as
    kilocalories, or grams entered as milligrams, is accepted.

Agents have a further problem. The server accepts Food Entries whose source is
Open Food Facts, but it offers no way to look a product up: the Platform Food
search operation covers USDA only. An agent logging a branded food has to supply
the nutrient values from somewhere else, so the agent and the app can log the
same barcode with different numbers.

## Goals

1.  **Offline search and barcode lookup for common products.** The app ships a
    bundle of Open Food Facts products. For each launch country (AU, US, UK, CA,
    NZ), the bundle takes up to 10,000 products that Open Food Facts lists for
    that country, that have been scanned at least once, and that have a name
    and known energy, protein, carbohydrate and fat (from Open Food Facts'
    `_100g` fields, which hold per-100 g or per-100 ml values). It ranks them by
    scan count and merges the five lists with no duplicate barcodes. With the
    network off:
    *   typing in the picker returns matching bundled products as the user
        types, within 100 ms after the 300 ms typing pause ends, on the
        reference device (see [Performance and storage](#performance-and-storage));
    *   scanning or typing a bundled product's barcode finds it.
2.  **The bundle stays small.** It adds no more than 6 MB to the compressed
    app download on either platform.
3.  **Live search returns a list, and only when asked.** Live search runs when
    the user taps the online search row or uses the keyboard's search action in
    the Open Food Facts filter, never while typing. It returns up to 20
    products.
4.  **One product, one row.** A barcode that exists in more than one place (the
    bundle, the device cache, a live result) appears once in the picker. The
    copy with the later change date wins.
5.  **Products the user opens or scans stay available offline.** A live product
    the user opens or scans is kept in the device cache and can then be searched
    and scanned offline, until the user erases all data or the operating system
    clears the app's cache directory.
6.  **The app follows Open Food Facts' rules.**
    *   Every request sends `User-Agent: Perennia/<app version> (<contact email>)`.
    *   The app sends at most 10 search requests and 15 product requests per
        minute. A request over that limit is not sent.
    *   Nothing is retried automatically.
    *   Barcode lookups use the current product API (v3.6).
7.  **Every Open Food Facts food explains its source.**
    *   In the picker and on the log-portion screen, an Open Food Facts food
        carries the source badge with "ODbL" (`FoodSourceBadge` with
        `showLicense: true`) and the attribution notice.
    *   On the log-portion screen, the notice also shows a link to the
        product's Open Food Facts page, the disclaimer, and the change date when
        it is known. Items from the Recent list get the link and the disclaimer
        too.
    *   On the Nutrition Day view, a logged Food Entry whose source is Open Food
        Facts carries the badge without the licence label
        (`showLicense: false`), as imported entries already do.
    *   The About screen states the disclaimer, the dataset version, and where
        the bundle, its licence file and its builder are in the repository.

    The disclaimer text is: "Values come from Open Food Facts contributors and
    may be incomplete or wrong. Check the label. Not for medical use."
8.  **Online lookups can be turned off.** A device setting, "Look up foods
    online", is on by default. When it is off, the app sends nothing to Open
    Food Facts, and search and scanning use only the bundle and the device cache.
9.  **Agents get the same bundle.** The existing Platform Food search operation
    and its MCP tool can search the bundle by name or by barcode. For a bundled
    barcode they return the record in that barcode's line of the bundle (name,
    values, serving and package sizes, brand and change date), with an
    attribution object that carries the licence, the disclaimer and the
    bundle's dataset version. An app with the same dataset version decodes the
    same record from its bundle; it may show a newer device-cache copy instead
    (Goal 4). Search order may differ from the app's. The server makes no calls
    to Open Food Facts.
10. **The licence obligations are met in the repository.** The bundle file has
    an ODbL licence file next to it. A third-party data notice at the repository
    root lists every dataset the repository ships with its licence (Open Food
    Facts, USDA, and the existing platform exercise data), so that one file says
    what data Perennia distributes and on what terms. The tool that builds
    the bundle is committed, and running it again on the same Open Food Facts
    dump produces the same product lines.

## Non-Goals

*   **More USDA foods.** The USDA catalogue stays at its current three foods.
    Generic foods (rice, chicken, an apple) need a separate data change, with its
    own spec.
*   **Bundles for other countries, or downloadable country packs.** Users
    outside the five launch countries get little from the bundle and rely on
    live search.
*   **Live lookups for agents.** Agents search the bundle only and cannot find a
    product outside it. An agent can still log such a product by supplying its
    values, as it can today.
*   **Writing to Open Food Facts:** adding products, correcting values or
    uploading photos. The product link lets the user do that on the Open Food
    Facts site.
*   **Product photos.** They are under a different licence (CC BY-SA 3.0) and
    can show third-party trademarks.
*   **Scores and labels:** Nutri-Score, NOVA group, Eco-Score, ingredients and
    allergens. Allergen data is safety information, and crowdsourced values must
    not be presented as reliable for it.
*   **Changing logged history.** When a product's values change (a newer bundle
    or a newer live copy), existing Food Entries keep the snapshot they were
    logged with. Re-logging from the Recent list logs the Recent snapshot, as
    today.
*   **Showing the user how bundled and live values differ.** The newer copy is
    used, without a comparison view.
*   **A Food Library screen** on the Library root. Browsing and managing User
    Foods and Recipes is separate work; this spec changes only how branded
    products are found and attributed.
*   **A legal opinion.** The agent API serves synced Food Entry snapshots that
    contain Open Food Facts values. Before public release, a lawyer checks
    whether ODbL section 4.6 needs more than the published code and bundle. The
    answer may require a follow-up, such as an export of those snapshots.

## Open Questions

*   **The contact email in the User-Agent.** Open Food Facts asks for
    `AppName/Version (ContactEmail)`. The value is one constant,
    `openFoodFactsContactEmail` (see file 16), and it must be a project address,
    not a personal one. The maintainer supplies it before pull request 2 merges.

Two questions are deferred, not blocking: the legal check above, and a kilojoule
fallback for energy (see [Future Improvements](#future-improvements)).

## Critical User Journeys (CUJs)

### CUJ 1: Scan a common product with no signal

*   **Given**: the app and its bundle are installed (see
    [Installing the bundle on the device](#installing-the-bundle-on-the-device)).
    The device has no network. The user holds a product that is in the bundle.
*   **When**: the user opens the add-food picker for a Meal, taps **Scan
    barcode**, and scans the product.
*   **Then**: the log-portion screen opens for that product with no network
    request and no spinner. It shows the product name, the brand, the source
    badge "Open Food Facts - ODbL", and the attribution notice with the product
    link, the disclaimer and the change date. Tapping **Log** saves a Food Entry
    whose snapshot carries `foodSource: openFoodFacts` and the product's values.
    Saving does not wait on anything but the local database.

### CUJ 2: Search the bundle while typing

*   **Given**: the bundle is installed. The network state does not matter.
*   **When**: the user selects the **Open Food Facts** filter in the picker and
    types "chobani gr".
*   **Then**: within 100 ms after the 300 ms typing pause ends, the list shows
    bundled and device-cache products whose name or brand has words starting
    with "chobani" and "gr". No request goes to Open Food Facts while the user
    types.

### CUJ 3: Scan or type a barcode that is not on the device

*   **Given**: "Look up foods online" is on. The product is in neither the bundle
    nor the device cache.
*   **When**: the user scans its barcode, or types the barcode digits into the
    search field of the Open Food Facts filter and uses the keyboard's search
    action.
*   **Then**:
    *   **Online, product exists:** one product request is sent. The
        log-portion screen opens for the product, and the product is saved to
        the device cache.
    *   **Online, product unknown to Open Food Facts:** the existing not-found
        state appears, offering **Quick add** (which creates a Quick Entry) and
        creating a User Food.
    *   **Offline:** no request is sent. The not-found state appears with the
        line "You're offline. Showing foods on this device."

### CUJ 4: Find a product that is not on the device by name

*   **Given**: the device is online, "Look up foods online" is on, and the
    product is in neither the bundle nor the device cache.
*   **When**: the user types its name and taps the online search row (or uses the
    keyboard's search action) in the Open Food Facts filter.
*   **Then**: one search request is sent. Up to 20 results appear in a second
    group below the device's own matches, with no product shown twice. A result
    that is already on the device with a later change date takes the place of
    the device's copy in the first group. When the user opens a result, it is
    saved to the device cache; when the user later searches for it offline, it
    appears with the device's matches.

### CUJ 5: Open Food Facts is unavailable, or the user searches too often

*   **Given**: the device is online and "Look up foods online" is on.
*   **When**: the user submits an 11th online search within 60 seconds, or Open
    Food Facts answers with HTTP 429 or 503, or with a body that does not parse.
*   **Then**: the list shows "Open Food Facts is unavailable. Try again in a
    minute." In each case the device's own matches stay on screen, nothing
    retries on its own, and Quick add stays available.

### CUJ 6: The user turns online lookups off

*   **Given**: the user turns off **Settings > Food data > Look up foods
    online**.
*   **When**: the user types a query, submits a search, or scans a barcode that
    is not on the device.
*   **Then**: no request goes to Open Food Facts. The online search row is
    replaced by "Online lookups are off. Turn them on in Settings > Food data." A
    scanned barcode that is not on the device shows the existing not-found
    state with the same line.

### CUJ 7: An agent finds and logs a branded product

*   **Given**: an agent has an API key for the user's account.
*   **When**: the agent calls
    `GET /agent/foods/platform-search?source=openFoodFacts&search=<code>` (or
    the MCP tool `agent_search_platform_foods` with the same input), then logs
    the result with the existing meal batch-write operation
    (`POST /agent/meals/batch-write`, command `log-meal`).
*   **Then**: for a bundled product, the first food in the response is the
    record in that barcode's line of the bundle, plus an attribution object with
    the licence, the disclaimer, the dataset version and the repository location
    of the bundle. For a barcode outside the bundle, `foods` has no product with
    that code. No request goes to Open Food Facts.

### CUJ 8: A maintainer refreshes the bundle

*   **Given**: a newer Open Food Facts dump exists.
*   **When**: a maintainer downloads it, runs the bundle builder, checks the
    report, and commits the new bundle file in a pull request.
*   **Then**: users who install the next app version get the new bundle on first
    launch, because its content hash differs. A product in the device cache with
    a later change date than the new bundle's copy keeps the device-cache copy.
    A product the user scanned or opened stays on the device even when the new
    bundle no longer contains it. Food Entries logged before the refresh keep
    their snapshots.

### CUJ 9: The app is killed while the bundle installs

*   **Given**: the first launch after an install or update has started
    installing the bundle.
*   **When**: the app is killed before the install finishes, and reopened.
*   **Then**: the install starts again from the beginning, and once it finishes
    the device holds exactly one complete copy of the bundle. Logging Sets, Food
    Entries and Doses worked throughout, because the bundle lives in a separate
    database file and installs on a separate isolate (see
    [Installing the bundle on the device](#installing-the-bundle-on-the-device)).

## Technical Plan (Architecture)

### Overview of the parts

```text
 Maintainer, offline                            Repository
 ┌──────────────────────────────────┐  writes   ┌──────────────────────────────────────┐
 │ apps/mobile/tool/open_food_facts │──────────▶│ apps/mobile/assets/seeds/            │
 │ _bundle/build_bundle.dart        │           │   open_food_facts_bundle.ndjson.gz   │
 │  reads the Open Food Facts dump  │           │   open_food_facts_bundle.LICENSE.md  │
 │  maps with the app's Dart code   │           └──────────────┬───────────────┬───────┘
 └──────────────────────────────────┘                          │ app asset     │ copied into the
                                                               ▼               ▼ server image
 App (device)                                             Server
 ┌──────────────────────────────────────────┐             ┌─────────────────────────────────┐
 │ Picker / scanner / log-portion screen    │             │ GET /agent/foods/platform-search│
 │        │                                 │             │   source=openFoodFacts          │
 │        ▼                                 │             │ MCP agent_search_platform_foods │
 │ OpenFoodFactsRepository (own provider)   │             │        │                        │
 │  ├─ FoodReferenceDatabase (own file)     │             │        ▼                        │
 │  │    products table + FTS5 index        │             │ in-memory map by barcode +      │
 │  │    bundle rows and device-cache rows  │             │ word-prefix filter, loaded once │
 │  ├─ bundle installer (own isolate)       │             │ (no outbound requests)          │
 │  └─ OpenFoodFactsClient (HTTP)           │             └─────────────────────────────────┘
 │       User-Agent, request budget         │
 └───────┬──────────────────────────────────┘
         │ search.pl / API v3.6 (user action only)
         ▼
   world.openfoodfacts.org (rate-limited)
```

There is one product mapping, written in Dart, in the app's pure domain layer
(no Flutter imports). The app's live path and the bundle builder both use it,
so a bundled product and the same product fetched live produce the same record.
The server never maps products: it reads the bundle's already-mapped records.

One rule is shared by the app and the server and checked by golden vectors in
both languages ([ARCHITECTURE.md](../../ARCHITECTURE.md#validation)): turning a
scanned or typed code into the list of barcodes to try.

### The product mapping

The mapping already exists in Dart (`_openFoodFactsRecordFromProduct` and its
helpers in `training_repositories.dart`). This spec moves it into the domain
layer and changes it as follows.

Kept as they are:

*   **Name:** `product_name`, then `product_name_en`, then `generic_name`.
*   **Nutrients:** the existing key list and unit multipliers (sodium,
    cholesterol and caffeine from grams to milligrams). Negative values are
    dropped as unknown.
*   **Serving and package:** parsed from `serving_quantity`,
    `serving_quantity_unit`, `serving_size`, `product_quantity`,
    `product_quantity_unit` and `quantity`, which also decide `isLiquid`.
*   **Food id:** the barcode.

Changed:

*   **Energy:** only `energy-kcal_100g`. The `energy-kcal_value` fallback is
    removed, because it is on the label's basis, which can be per serving.
*   **Brand (new):** the first comma-separated entry of `brands`, trimmed;
    `null` if empty.
*   **Change date (new):** `last_modified_t`, in Unix seconds.
*   **Scan count (new):** `unique_scans_n`, or `null`.
*   **Exclusions.** The mapping returns "excluded" with one of four reasons:
    *   `missingCode` — no barcode;
    *   `missingName` — no name by the rule above;
    *   `missingChangeDate` — no `last_modified_t`, because the newer-copy rule
        needs it;
    *   `implausible` — a value that cannot be right per 100 g or ml: energy
        above 900 kcal, or protein, carbohydrate, sugar, fat, saturated fat,
        monounsaturated fat, polyunsaturated fat or fibre above 100 g.

    A product with unknown nutrients is not excluded; its values stay unknown.
    The existing Food Entry validator is not called here: its limits are per
    entry (10,000 kcal; 2,000 g per macro), so they would exclude nothing at
    100 g. Logging still runs that validator as today.
*   **Nutrient text.** Each known value is formatted once with the existing
    rule (six decimal places, trailing zeros and point removed) into its
    `entered` text. The numeric value is that text parsed back, so the app and
    the server read the same number from the same text.

### Building the bundle

`apps/mobile/tool/open_food_facts_bundle/build_bundle.dart` is a maintainer
tool, run from `apps/mobile`:

```text
dart run tool/open_food_facts_bundle/build_bundle.dart \
  --input <path to openfoodfacts-products.jsonl.gz> \
  --dataset-version <YYYY-MM-DD>
```

It runs with `dart run`, as `tool/generate_design_tokens.dart` already does,
and imports only the domain mapping, which has no Flutter imports.

Its input is Open Food Facts' JSONL dump
(`https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz`;
13.3 GB compressed when checked on 2026-10-26, updated daily). Each line is one
product object with the same fields the API returns, so the mapping reads it
with no adapter. `--dataset-version` is the dump's `Last-Modified` date.

The builder:

1.  Streams the file through gzip decoding and splits it into lines. A line
    that contains none of the five country tags as text (`en:australia`,
    `en:united-states`, `en:united-kingdom`, `en:canada`, `en:new-zealand`) is
    skipped before it is decoded, to save time.
2.  Decodes each remaining line, maps it, and keeps it when the mapping did not
    exclude it, energy, protein, carbohydrate and fat are known, and
    `unique_scans_n` is greater than 0.
3.  For each country tag listed in the product's `countries_tags`, adds it to
    that country's candidates. Each country keeps its best 10,000 by
    `unique_scans_n` descending, then `code` ascending.
4.  Merges the five lists, removes duplicate codes, and sorts by `code`
    ascending (string order).
5.  Writes the header and the product lines (see below), gzips the result, and
    writes `apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz`.
6.  Prints a report: products per country before and after the limit, products
    excluded by reason, products dropped for missing core nutrients or zero
    scans, the merged count, the compressed size, and the run time. It exits
    with an error if the compressed file is larger than 6 MB.

Running it again on the same dump produces the same product lines and the same
content hash. The gzip bytes may differ; nothing depends on them. Open Food
Facts replaces the dump daily and keeps no history, so reproducing an older
bundle needs the maintainer's copy of that day's dump. The ODbL obligation is
met by the committed bundle and the committed builder, not by the dump.

### The bundle file

`apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz` is a gzip-compressed
file of JSON lines: one header line, then one line per product, sorted by code.
Every line ends with a newline.

Header line (shown wrapped; one line in the file):

```json
{
  "format": "perennia-open-food-facts-bundle",
  "formatVersion": 1,
  "datasetVersion": "2026-10-26",
  "contentHash": "<SHA-256 of the product lines, lowercase hex>",
  "sourceName": "Open Food Facts",
  "sourceUrl": "https://world.openfoodfacts.org/",
  "licenseName": "Open Database License (ODbL) 1.0",
  "licenseUrl": "https://opendatacommons.org/licenses/odbl/1-0/",
  "contentsLicenseUrl": "https://opendatacommons.org/licenses/dbcl/1-0/",
  "attributionText": "Contains information from Open Food Facts, made available under the Open Database License (ODbL) 1.0. The bundle, its licence file and the tool that builds it are in the Perennia repository: apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz, apps/mobile/assets/seeds/open_food_facts_bundle.LICENSE.md and apps/mobile/tool/open_food_facts_bundle/build_bundle.dart.",
  "countries": ["au", "us", "gb", "ca", "nz"],
  "perCountryLimit": 10000,
  "productCount": 41234
}
```

`contentHash` is the SHA-256 of the bytes that follow the header line's newline,
up to the end of the uncompressed file.

Product line (shown wrapped; one line in the file):

```json
{
  "code": "0818290014313",
  "name": "Greek Yogurt Plain Nonfat",
  "brand": "Chobani",
  "isLiquid": false,
  "servingLabel": "serving",
  "servingSize": 170,
  "packageSize": 907,
  "nutrients": { "energy": "53", "protein": "10", "carbohydrate": "3.6", "fat": "0" },
  "modifiedAt": 1745020800,
  "scans": 412
}
```

*   Every key is always present, in the order shown, written with no extra
    whitespace.
*   `code`, `name`, `isLiquid`, `nutrients`, `modifiedAt` and `scans` are never
    `null`. `brand`, `servingLabel`, `servingSize` and `packageSize` are written
    as `null` when unknown.
*   `nutrients` maps Nutrient ids, as written in `usda_foods.json` (for example
    `saturated_fat`), to the value per 100 g or ml as text, in the Nutrient's
    default unit. A Nutrient that is absent is unknown, never zero
    ([CONTEXT.md](../../CONTEXT.md#nutrient)). A reader takes the text as
    `entered` and the parsed number as `value`.
*   `modifiedAt` is the change date in Unix seconds. `scans` is
    `unique_scans_n`, used only to rank.

The licence file sits next to the bundle file as
`apps/mobile/assets/seeds/open_food_facts_bundle.LICENSE.md` and is listed in a
new root `THIRD_PARTY_DATA.md`. It is not bundled into the app; the About screen
names its repository path.

### Bundle size

From a sample of the 100 most-scanned Australian products with complete
nutrition, fetched from the Open Food Facts API on 2026-10-25, a compact product
line averages 233 bytes before compression and 62 bytes after. About 41,000
products gives about 2.5 MB; writing nutrient values as text adds a few
percent. The builder's size check enforces the 6 MB budget. Requiring at least
one scan may leave fewer than 10,000 products for the smaller countries; the
builder's report shows how many.

### Where the bundle is stored

The bundle file is committed to git like the other seeds. A refresh adds about
2.5 MB to the repository history, and refreshes are planned at most once a
quarter, with an app release. Git LFS and release-asset downloads were rejected
(see [Alternative F](#alternative-f-store-the-bundle-outside-plain-git)).

### Installing the bundle on the device

The bundle does not go into the user's database (`AppDatabase`). It goes into a
second Drift database, `FoodReferenceDatabase`, stored as `food_reference.sqlite`
in the app's cache directory. The reasons:

*   It is reference data that can be rebuilt at any time. Keeping it out of the
    user's database keeps it out of sync, backups and the portable archive, and
    keeps the user's database small.
*   Writing about 41,000 rows takes seconds. In a separate file, written from a
    separate isolate, it cannot hold a lock or take UI-isolate time that a Set
    or Food Entry save needs ([AGENTS.md](../../AGENTS.md#non-negotiable-invariants):
    a save confirms within one frame).
*   If the operating system clears the cache directory, the app rebuilds the
    bundle on the next launch. Only the device cache is lost, and it can be
    fetched again.

Its schema:

| Table | Columns |
| :---- | :------ |
| `reference_meta` | `key` text primary key, `value` text. One key: `bundle_content_hash`. |
| `open_food_facts_products` | `id` integer primary key (autoincrement, the FTS5 row id); `code` text, unique; `name` text; `brand` text nullable; `is_liquid` boolean; `serving_label` text nullable; `serving_size` real nullable; `package_size` real nullable; `nutrients_json` text (the compact form); `modified_at` integer; `scans` integer nullable; `origin` text, `bundle` or `online` (why the row is kept; see [One product, one row](#one-product-one-row)). |
| `open_food_facts_products_fts` | FTS5 virtual table over `name` and `brand`, external content `open_food_facts_products` with `content_rowid='id'`, tokenizer `unicode61 remove_diacritics 2`, kept in step by insert, update and delete triggers. |

Every connection is opened with `PRAGMA journal_mode=WAL` and
`PRAGMA busy_timeout=5000`. With WAL, a reader on one connection is never
blocked by a writer on another; the busy timeout makes a second writer wait for
the lock instead of failing at once. The database is never vacuumed, so the
integer row ids stay stable for FTS5. It has no migrations: when its schema
version changes, `onUpgrade` drops every table and creates the schema again,
and the missing content hash makes the installer run.

On each app start, after the first frame:

1.  The repository resolves `food_reference.sqlite` in the cache directory,
    opens the app's connection to `FoodReferenceDatabase` (creating the schema
    on first use), and reads `bundle_content_hash`.
2.  On the UI isolate, it loads the asset's bytes with `rootBundle.load` (about
    2.5 MB, a single read) and decodes only the start of the gzip stream, up
    to the end of the header line (a few hundred bytes). If `format` or
    `formatVersion` is not the one this build knows, the status becomes
    `failed`. If `contentHash` equals the stored hash, the status becomes
    `ready` and nothing else happens.
3.  Otherwise it passes the bytes to `Isolate.run`. The isolate opens its own
    WAL connection to the same file and, in **one transaction**:
    1.  deletes every row whose `origin` is `bundle`;
    2.  decodes the gzip, splits the lines, and inserts each product with
        `origin = bundle`. When a row with the same code exists (it can only be
        an `online` row now), the bundle copy replaces its values only if its
        `modified_at` is greater, and the row stays `online`;
    3.  writes `bundle_content_hash`.
4.  When the isolate returns, the status becomes `ready`, or `failed` if it
    threw.

Every failure in these steps (resolving the cache directory, opening the
database, reading the asset, the isolate) sets the status to `failed`, is
reported to the opt-in crash reporter only, and is never thrown to the caller.
The next app start tries again.

Only one install runs at a time. A call to install while one is running returns
the running install. Erase all data waits for a running install to finish, then
resets the database and installs again (see
[One product, one row](#one-product-one-row)).

The repository holds the current status (`unknown` before the first check,
then `installing`, `ready` or `failed`). Its status stream gives a new listener
the current status first, then each change.

While the install runs, readers see the last committed state: on a refresh,
the previous bundle; on the first install, only the device cache, with the
status line "Preparing the offline food list." Because the install is one
transaction, a killed install leaves the previous state, and the next start
runs it again (CUJ 9). Drift stream queries on the app's connection do not see
writes made on the isolate's connection, so the picker searches again when the
status becomes `ready`.

The old cache table `open_food_facts_cache` in `AppDatabase` is dropped in
schema version 61. Its rows are not copied: the app has not been released, so no
user holds a cache worth keeping, and Food Entries and the Recent list do not
depend on it.

### One product, one row

The products table has one row per barcode, so the picker cannot show a product
twice. Two separate rules govern a row:

*   **Values:** an incoming copy replaces the stored values only if its
    `modified_at` is greater. This applies to bundle installs and to live
    products the user opens or scans.
*   **`origin` records why the row is kept, not where its values came from.**
    `bundle` means the row exists because the current bundle contains it.
    `online` means the user opened or scanned the product, so the device keeps
    it. A row becomes `online` when the user opens a live search result or a
    live barcode lookup finds the product. An incoming bundle copy never changes
    `online` back to `bundle`.

A live search stores nothing. When a live result shares a code with one of the
device's matches and has a greater `modified_at`, the picker shows the live
copy in that match's place; it is stored only if the user opens it.

Storing never delays the screen: when the user opens a live result or a live
barcode lookup finds a product, the log-portion screen opens with the live copy
at once, and the write runs in the background. During a first install it can
wait up to the 5-second busy timeout for the install's lock; if it still fails,
the product is simply not kept, and the failure goes to the opt-in crash
reporter only.

There is no eviction. The device cache grows only by products the user opened
or scanned. A reinstall deletes only `bundle` rows, so a product the user opened
or scanned is never lost to a refresh, even when the new bundle drops it. Erase
all data resets the whole reference database: it deletes every row and the
stored content hash, then runs the installer, so the full bundle is back and the
device cache is empty.

### Search and barcode rules

**Barcode candidates** (golden-vectored, used by the app and the server):

*   Remove all whitespace and hyphens (the existing rule, `[\s-]`). The result
    must be 6 to 18 digits, or it is not a barcode and the candidate list is
    empty.
*   Candidates, in order: the code as given; if it has 12 digits, the code with
    a leading `0` (a UPC-A code, the 12-digit North American barcode, as Open
    Food Facts usually stores it); if it has 13 digits and starts with `0`, the
    code without it.

**Local search in the app**, run as the user types, after the 300 ms typing
pause:

1.  If the query has barcode candidates, the stored products with those codes
    come first.
2.  Then the FTS5 search. The query is lower-cased and split on every character
    that is not a Unicode letter or digit; empty parts are dropped and the first
    8 kept. Each part is written as a quoted prefix term (`"chobani"* "gr"*`),
    and all must match. The tokenizer folds diacritics, so "creme" finds
    "Crème".
3.  Order: `bm25` with name weighted 2 and brand weighted 1, then `scans`
    descending (no value counts as 0), then `code` ascending. The limit is 50.
4.  A query with no parts and no barcode candidates searches nothing, and the
    list shows "Type a product or brand name."

The Recent, User and USDA filters keep `foodNameMatchesQuery`, which matches
substrings. The Open Food Facts filter matches word prefixes. This is deliberate:
FTS5 needs whole-word prefixes to stay within the search budget over 41,000 rows.

**Barcode lookup in the app** (scan, or a barcode typed and submitted):

*   A stored product matching a candidate is used as it is, with no live
    refresh.
*   Without one, and with online lookups on, one live product request is sent
    for the code as given. A found product is saved to the device cache.

### Live requests

All live requests go through a new `OpenFoodFactsClient` in the repository
layer (only repositories touch the network, per
[ARCHITECTURE.md](../../ARCHITECTURE.md#the-app)):

| Request | Endpoint | Parameters |
| :------ | :------- | :--------- |
| Search | `GET https://world.openfoodfacts.org/cgi/search.pl` | `search_terms`, `search_simple=1`, `action=process`, `json=1`, `page_size=20`, `page=1`, `sort_by=unique_scans_n`, `fields` |
| Product | `GET https://world.openfoodfacts.org/api/v3.6/product/<code>.json` | `fields` |

*   **`fields`:** `code`, `product_name`, `product_name_en`, `generic_name`,
    `brands`, `nutriments`, `serving_quantity`, `serving_quantity_unit`,
    `serving_size`, `product_quantity`, `product_quantity_unit`, `quantity`,
    `unique_scans_n`, `last_modified_t`.
*   **Search endpoint:** full-text search is not in API v2 or v3. `search.pl` is
    the legacy endpoint the Open Food Facts documentation still lists for it.
    Search-a-licious is the planned replacement, but it reports version 0.1.0
    (see [Alternative G](#alternative-g-search-a-licious-instead-of-searchpl)).
*   **User-Agent:** `Perennia/<version> (<contact email>)`. `<version>` is the
    part of the shared app version constant before `+`. `<contact email>` is the
    constant `openFoodFactsContactEmail` (see [Open Questions](#open-questions)).
    Forks change the constant.
*   **Request budget:** an in-memory window per request kind: at most 10
    search and 15 product requests in any 60 seconds. A request over the budget
    is not sent. Restarting the app clears the window; the risk is low, because
    a user would have to restart repeatedly to exceed the limit.
*   **Timeouts:** 10 seconds per request.
*   **Outcomes:** the client returns one of `results` (with products), `notFound`
    (HTTP 404, or v3 `status: failure` with `result.id: product_not_found`),
    `offline` (no connection or a timeout), or `unavailable` with a reason kept
    for tests: `rateLimited` (HTTP 429), `busy` (HTTP 503), `httpError` (any
    other non-2xx status), `malformed` (a body that does not parse) or
    `budgetExceeded` (the local request budget; nothing was sent). The user sees
    the same "unavailable" line for every reason. Products in a response are
    mapped; excluded products are left out. Nothing is retried.
*   **The setting:** `AddFoodRepository` reads the device setting
    `onlineFoodLookups` (default on) and passes it to the Open Food Facts
    repository as `allowOnline`. When it is false, the repository returns
    `disabled` without sending anything. The setting is stored with the other
    device-level settings in the local settings file (`FileSettingsRepository`).
    It is not synced to other devices, but like every device setting it travels
    with Backup/Restore.
*   **What is sent** (the single list this spec refers to elsewhere): only the
    search text or barcode, the User-Agent and an `accept` header, over HTTPS.
    No account id, device id, location or Perennia server address. A request is
    sent only after a user action: submitting an online search, or scanning or
    submitting a barcode that is not on the device. Nothing is fetched in the
    background, and installing the bundle sends nothing.

### The picker, the scanner and the log-portion screen

With the **Open Food Facts** filter selected, the picker shows, from top to
bottom:

1.  **The bundle line**, when it applies: "Preparing the offline food list."
    while the status is `installing`; "The offline food list could not be
    prepared. It will try again next time the app opens." when it is `failed`.
    Nothing for `unknown` or `ready`.
2.  **The device's own matches** (bundle and device cache), from the local
    search as the user types. When the query has neither match parts nor
    barcode candidates, this group is replaced by the line "Type a product or
    brand name." and nothing below it is shown.
3.  **The online slot**, which shows exactly one of the following, checked in
    this order:

    | Condition | Shown |
    | :-------- | :---- |
    | Online lookups are off | "Online lookups are off. Turn them on in Settings > Food data." |
    | A live request is running | The online search row, with a progress indicator in place of its icon |
    | The last live request found no connection | "You're offline. Showing foods on this device." |
    | The last live request was unavailable | "Open Food Facts is unavailable. Try again in a minute." |
    | The last live search returned no products | "No matches on Open Food Facts." |
    | Otherwise | The **online search row**, labelled `Search Open Food Facts for "<query>"` |

    Tapping the online search row, or the keyboard's search action, submits the
    query (below). Changing the query clears the last live request's state.
4.  **"From Open Food Facts"**, the live results whose barcode is not among the
    device's matches, in the order Open Food Facts returned them. There is no
    paging: users refine the query instead.

**Submitting the query** (the online search row or the keyboard's search
action, in the Open Food Facts filter):

*   If the query has barcode candidates and one of the device's matches has a
    candidate code, that product opens on the log-portion screen and nothing is
    sent.
*   If the query has barcode candidates and no match, one live product request
    is sent. A found product opens on the log-portion screen; otherwise the
    barcode result below applies.
*   Otherwise, one live search is sent. When results arrive, a live result whose
    code is among the device's matches and whose change date is later takes
    that match's place in group 2 (Goal 4); the rest form group 4.

The other filters (Recent, User, USDA) keep their behaviour.

**Scanning** uses the barcode rules. The existing `BarcodeLookupStatus` values
are kept and two are added. Each miss shows the existing not-found state (Quick
add and creating a User Food) with one line:

| `BarcodeLookupStatus` | Line under the not-found state |
| :-------------------- | :----------------------------- |
| `notFound` | none |
| `needsNetwork` | "You're offline. Showing foods on this device." |
| `unavailable` (new) | "Open Food Facts is unavailable. Try again in a minute." |
| `disabled` (new) | "Online lookups are off. Turn them on in Settings > Food data." |

A typed barcode that is submitted and not found uses the same banner. The two
existing "needs network the first time" messages are removed.

A live request never puts the picker into `AsyncLoading`: the device's matches
stay on screen while it runs.

Styling follows [DESIGN.md](../../DESIGN.md): the online search row is a
standard list row with a leading search icon and primary text colour, not a
Signal Cyan action, so the screen keeps one primary accent. The bundle line and
the status lines use secondary text. Every new control is at least 48 dp tall.

**Attribution.** The existing `OpenFoodFactsAttributionNotice` is extended
rather than joined by a second widget. It gains two optional inputs, `code` and
`changeDate`. Both forms keep the existing source and ODbL links.

*   **Compact form** (the picker): its sentence becomes "Open Food Facts data,
    from its contributors. Check the label." It replaces "Open Food Facts
    branded data is live-query and cached on this device.", which the bundle
    makes false.
*   **Full form** (the log-portion screen): the existing sentence "Open Food
    Facts branded and barcode data is provided by Open Food Facts." and links;
    then, when `code` is set, a **View on Open Food Facts**
    `AttributionLinkButton` for `https://world.openfoodfacts.org/product/<code>`;
    the disclaimer; and, when `changeDate` is set, "Open Food Facts data from
    <date>", formatted with `DateFormat.yMMMd` in the device's locale and local
    time zone.

`AttributionLinkButton` shows the URL in a dialog where it can be copied; it
does not open a browser. This spec keeps that behaviour, which needs no new
dependency.

On the log-portion screen, an Open Food Facts food shows its brand under the
name when known, and the full notice. A food opened from the Recent list carries
its barcode as its Food id, so it gets the product link and the disclaimer; its
change date is not in the snapshot, so the date line is left out.

`PlatformFoodRecord` and `FoodPickerItem` gain three nullable fields, `brand`,
`sourceModifiedAt` and `scans`, which are `null` for USDA and User Foods.
`FoodPickerItem` also gains `isLiveResult` (default `false`), which marks a live
copy that is not stored, so opening it stores it. A Food Entry's snapshot is
unchanged: it keeps the product name, values and source, not the brand or the
change date.

On the Nutrition Day view, every Food Entry whose snapshot source is Open Food
Facts shows `FoodSourceBadge(source: FoodSource.openFoodFacts, showLicense: false)`,
in the slot imported entries use.

The About screen's Open Food Facts paragraph becomes:

> Branded foods come from Open Food Facts, a database built by its
> contributors, made available under the Open Database License (ODbL) 1.0. This
> app includes a list of common products from Australia, the United States, the
> United Kingdom, Canada and New Zealand (dataset version <datasetVersion>,
> <productCount> products). The list and its licence file are in the Perennia
> repository under apps/mobile/assets/seeds/, and the tool that builds it is
> apps/mobile/tool/open_food_facts_bundle/build_bundle.dart. Values come from
> Open Food Facts contributors and may be incomplete or wrong. Check the label.
> Not for medical use. Searching online sends your search text or barcode to
> Open Food Facts; you can turn this off under Settings > Food data.

While the bundle header is loading, or if it cannot be read, the parenthesis
"(dataset version …, … products)" is left out. The paragraph is followed by the
existing source and ODbL links and a DbCL link.

The About screen's offline paragraph, which today says Open Food Facts lookups
"need network once", becomes:

> USDA foods and the offline Open Food Facts list work with no network.
> Searching Open Food Facts online needs a connection, and products you open or
> scan stay on this device. Quick Entry stays available.

### Agent surface

The existing operation (operationId `searchAgentPlatformFoods`,
`GET /agent/foods/platform-search`, command-map name `search-platform-foods`,
MCP tool `agent_search_platform_foods`) already has a `source` parameter,
limited to `usda`, reserved for this. This spec widens it.

Request:

| Parameter | Change |
| :-------- | :----- |
| `source` | Enum becomes `usda` \| `openFoodFacts`. Default stays `usda`. |
| `search`, `limit` | Unchanged. With `source=openFoodFacts`, `search` takes a name or a barcode, like the app's single search box. |

No new parameter is added: a barcode is searched through `search`. Responses:

*   `source=openFoodFacts` with no `search`, or with a `search` that has neither
    word parts nor barcode candidates, returns 200 with empty `foods`. Listing
    the whole bundle is not supported.
*   If the bundle file cannot be read, the response is HTTP 503 with the
    existing `AgentFoodsUnavailableResponseSchema` and the message "The Open Food
    Facts bundle is not available on this server." The route's 503 schema
    becomes the union of `AgentApiKeyUnavailableResponseSchema` and
    `AgentFoodsUnavailableResponseSchema`, as `agentFoodListRoute` already
    declares. The MCP tool returns the same body through `errorResult`, as the
    food batch-write tool does.

Search on the server, over the bundle only:

1.  If `search` has barcode candidates, the products whose codes match come
    first, in candidate order.
2.  Then name matches: names, brands and the query are normalized the same way
    (Unicode NFKD, combining marks removed, lower-cased, split on non-letters
    and non-digits). A product matches when every query part, up to 8, is a
    prefix of some word in its name or brand. Order: `scans` descending, then
    `code` ascending.
3.  Duplicates are removed, then `limit` applies (default 20, maximum 50, the
    existing constants).

The server's matches and order can differ from the app's FTS5 search. The
record for a given barcode is the one in that barcode's line of the bundle, which
an app with the same dataset version decodes identically.

Response:

*   Each food gains `brand`, `sourceModifiedAt` (ISO-8601, UTC) and
    `productUrl`, all nullable and `null` for USDA. `nutrientsPer100` has the
    same shape as for USDA: every Nutrient id is present, built with the
    existing `nutrientVectorStorage` in `agent-foods.ts`. A nutrient the bundle
    reports is `complete`, with `entered` and `value` read from its text; any
    other is `{ status: "unknown", value: null, entered: null }` with its
    default unit.
*   `attribution.source` accepts `openFoodFacts`. `attribution` gains
    `disclaimer` (the Goal 7 text for Open Food Facts, `null` for USDA). For Open
    Food Facts, `datasetVersion`, `sourceName`, `sourceUrl`, `licenseName` and
    `attributionText` come from the bundle header, so the response says where
    the ODbL copy is.

The route summary becomes "Search the bundled USDA and Open Food Facts Platform
Food reference data." The `search` parameter's description becomes
"Case-insensitive name filter; with `source=openFoodFacts`, a name or a barcode.
Omit to list the bundled USDA catalog; with `source=openFoodFacts`, omitting it
returns no foods."

On the server, a new module `apps/server/src/open-food-facts-bundle.ts` reads the
bundle once, on the first Open Food Facts request, synchronously: gunzip, split,
and parse into a `Map` from code to record plus an array for name search. This
blocks the Node event loop, and so every request in flight on that process, for
an estimated few hundred milliseconds, once per process (recorded as a risk).
`searchAgentPlatformFoods` stays synchronous. The
barcode candidate rule lives in `apps/server/src/barcode-candidates.ts`.

The module resolves `../../mobile/assets/seeds/open_food_facts_bundle.ndjson.gz`
relative to its own directory, which is `apps/server/src` in development and
`apps/server/dist` in the image; both land on `apps/mobile/assets/seeds/`. The
Dockerfile's runtime stage copies the file to that absolute path. This departs
from the USDA seed, which the server reads from a generated TypeScript module so
that the image ships only `apps/server`: a 2.5 MB file is too large for a
generated module, and reading the same file in development and in the image
keeps one copy (see [Alternative O](#alternative-o-copy-the-bundle-into-the-server-package-at-build-time)).

The MCP tool takes the same input and returns the same output. The contract
diff shows the widened enum, the new response fields, the 503 union and the new
descriptions in
`packages/contract/openapi.json`, `agent-client.ts`, the Dart API client and the
agent command map. Widening an enum in a response is
additive, but a client that treats the `source` enum as closed can reject an
`openFoodFacts` value; before 1.0 this is accepted, and the contract diff makes
it visible in review.

### Invariants

| Invariant ([AGENTS.md](../../AGENTS.md#non-negotiable-invariants)) | How it holds |
| :--------------------------------------- | :----------- |
| Local writes never block on the network; a save confirms within one frame. | Logging uses the stored row. Live requests happen only before the log-portion screen opens. The bundle installs on its own isolate and connection, in a separate database file; the UI isolate only reads the asset bytes and decodes the header line. |
| Sets and Food Entries are self-describing; templates never rewrite history. | A Food Entry still snapshots values and source at log time. A bundle refresh or a newer live copy changes the products table only. |
| Derived analytics are computed, never stored or synced. | The bundle is reference data, not a derived result. The FTS5 index is a lookup index rebuilt mechanically from its table. |
| Sync is silent last-writer-wins. | `FoodReferenceDatabase` does not sync. Open Food Facts data reaches the server only inside Food Entry snapshots, as today, and the server makes no calls to Open Food Facts. |
| Validation is one shared two-tier module. | No rule or tier changes. The mapping's plausibility exclusion is a data-selection rule, not validation; logging runs the validator as today. |
| No behavioral analytics. | Requests carry only what [What is sent](#live-requests) lists. The setting turns them off. |
| Local-only Mode transmits nothing (CONTEXT.md). | Amended in this spec (see [Vocabulary](#vocabulary)): reference lookups the user starts are the one exception, and the setting turns them off. |
| Restore and import are merge-only; delete is archive. | Not touched. The reference database is not part of backups or the portable archive. |

### Vocabulary

[CONTEXT.md](../../CONTEXT.md) changes, in the implementation pull request:

*   **Platform Food (new)** — a read-only Food whose facts come from an external
    Food Source (USDA or Open Food Facts), either shipped with the app or fetched
    from the source; the food-domain analog of the Platform Library.
    Customizing one forks a User Food.
*   **Food Source** gains: "An Open Food Facts Food comes from the bundle shipped
    with the app or from a live lookup; the copy Open Food Facts changed most
    recently is the one used."
*   **Local-only Mode** gains: "The one exception is a reference lookup the user
    starts, such as an online food search, which sends only the search text or
    barcode and can be turned off."

### Validation and analytics

*   No validation rule changes, and no tier changes.
*   No analytics computation changes. Nutrition totals keep reading Food Entry
    snapshots.
*   One new golden-vector fixture, `packages/golden-vectors/vectors/m36-barcode-candidates.json`
    (domain `barcode-candidates`, in the repository's milestone-numbered naming).
    It is run by a Dart runner and a TypeScript runner and registered in both
    ownership guards.
*   The mapping and the FTS5 match rule have one implementation each, in Dart,
    covered by Dart unit tests rather than golden vectors.

## Alternatives Considered

### Alternative A: Live lookups only, no bundle

*   **Pros**: No data pipeline, no repository growth, no ODbL file to manage,
    always the newest values.
*   **Cons**: With no signal, a user finds no branded product they have not
    looked up before. Every new product costs a request against a limit of 10
    searches a minute, and `search.pl` returned HTTP 503 during the research
    for this spec.
*   **Reason for Rejection**: It fails the gym-floor case the app is built for.

### Alternative B: Other ways to choose the bundled products

*   **Worldwide most-scanned list.** Simplest to build, but Open Food Facts
    contributions skew towards France, so it would hold mostly products that
    users in the launch countries never see.
*   **Per-country packs downloaded on first use.** Covers every country, but
    the first offline use needs a download, and the packs need hosting outside
    the app.
*   **Every country pack built into the app.** Works offline everywhere, but
    multiplies the download size.
*   **A secondary popularity signal** for the tail of each list. More products
    per country, but each extra signal needs its own justification; requiring
    at least one scan is enough to drop the arbitrary tail.
*   **Reason for Rejection**: The launch-country list gives a predictable size
    and covers the markets the app targets first.

### Alternative C: Put the bundle in the user's database

*   **Pros**: One database file, one Drift class.
*   **Cons**: About 41,000 reference rows would enter the database that syncs, is
    backed up and goes into the portable archive. Installing them would write to
    the file Set saves use. Every change to the bundle's shape would need an
    `AppDatabase` migration.
*   **Reason for Rejection**: Reference data that can be rebuilt does not belong
    with user-authored data.

### Alternative D: Ship a ready-built SQLite file instead of JSON lines

*   **Pros**: No install step on the device.
*   **Cons**: The download would include the FTS5 index as well as the data. On
    Android, assets are inside the app package, so the file would still have to
    be copied out before SQLite can open it.
*   **Reason for Rejection**: A smaller download and a simple text format are
    worth a few seconds of background work once per bundle version.

### Alternative E: Load the bundle into memory on the device, as the USDA seed is

*   **Pros**: Reuses `UsdaFoodSeedSource`.
*   **Cons**: About 41,000 decoded records take an estimated 15 to 30 MB of
    memory on the device, and a linear match over them ranks nothing.
*   **Reason for Rejection**: The USDA pattern fits three foods. (The server does
    use an in-memory map; its search has no latency target and no ranking
    requirement.)

### Alternative F: Store the bundle outside plain git

*   **Git LFS.** Keeps history small, but CI clones use up GitHub's free LFS
    bandwidth, and every contributor needs LFS installed.
*   **A release asset fetched at build time.** Keeps history small, but builds
    then need the network and a hosted file, and the ODbL "keep open" copy moves
    from the repository to a download that can disappear.
*   **Reason for Rejection**: Adding about 2.5 MB of history per quarter is
    accepted so that builds work from a plain clone.

### Alternative G: Search-a-licious instead of `search.pl`

*   **Pros**: The planned replacement for full-text search, with a documented
    API (`GET /search` with `q`, `page`, `page_size`, `fields`, `sort_by`).
*   **Cons**: It reports version 0.1.0, publishes no rate limits, and the Open
    Food Facts API documentation does not list it as the supported search path.
*   **Reason for Rejection**: `search.pl` is the path the documentation lists
    today. It sits behind one client method, so switching later changes one file
    and its tests.

### Alternative H: Route all app lookups through the Perennia server

*   **Pros**: One live client and one cache.
*   **Cons**: The app would need an account and a server to look anything up,
    which breaks the rule that the app is complete with no account and no
    network. Every user would share the server's single rate limit.
*   **Reason for Rejection**: It contradicts the offline-first design in
    [ARCHITECTURE.md](../../ARCHITECTURE.md).

### Alternative I: Live lookups on the server for agents

*   **Pros**: Agents could find products outside the bundle, as the app can.
*   **Cons**: A second live client, a server-wide request budget shared by every
    agent of every user (10 searches a minute), a cache of live results that
    would show one user's lookups in another's results, operator settings, and
    response fields for live status. Open Food Facts advises high-traffic
    clients to host their own instance or use the daily exports, not to proxy.
*   **Reason for Rejection**: Parity is met by giving agents the same operation
    over the same bundle, and the server stays deterministic with no outbound
    calls, as the existing comment in `agent-foods.ts` already chose.

### Alternative J: A new agent operation for Open Food Facts

*   **Pros**: A response shape designed only for Open Food Facts.
*   **Cons**: Two operations and two MCP tools that do the same thing for two
    sources. The existing operation already reserves the `source` parameter.
*   **Reason for Rejection**: Widening the existing operation is the change its
    design anticipated.

### Alternative K: FTS5 on the server through `node:sqlite`

*   **Pros**: The same matches and order as the app.
*   **Cons**: `node:sqlite` is experimental in Node 22. The server would copy the
    app's table, FTS5 table and triggers. No Goal asks for the same order, only
    the bundle's record for each barcode.
*   **Reason for Rejection**: A map and a word-prefix filter meet Goal 9 with no
    experimental dependency.

### Alternative L: The official Open Food Facts Dart SDK

*   **Pros**: Maintained models, User-Agent handling and endpoint coverage.
*   **Cons**: A large dependency for two GET requests, whose models change on
    their own schedule; the mapping would still be Perennia's own.
*   **Reason for Rejection**: It saves little code.

### Alternative M: Pick the winning copy by fetch time

*   **Pros**: No dependency on an Open Food Facts field.
*   **Cons**: A bundle installed after an app update would count as newer than a
    live copy fetched last week, even when the live copy holds a newer revision.
*   **Reason for Rejection**: The change date records when the product data
    actually changed, so it orders bundle and live copies correctly.

### Alternative N: "Look up foods online" off by default, or off with no account

*   **Pros**: Nothing leaves the device until the user opts in.
*   **Cons**: Live search and scan misses would fail until the user finds the
    setting. A default that depends on having an account adds a second code path
    and a settings change at sign-in.
*   **Reason for Rejection**: Requests happen only on an explicit user action,
    carry no identity, and can be turned off; the About screen and the
    Local-only Mode definition say so.

### Alternative O: Copy the bundle into the server package at build time

*   **Pros**: The image would ship only `apps/server`, like the USDA seed.
*   **Cons**: Development and the image would read different copies, or the
    server build would need a copy step in both the Dockerfile and local builds.
*   **Reason for Rejection**: One file read from one relative path in both
    places is simpler. The Dockerfile copies it with an absolute path.

### Alternative P: Other builder inputs and languages

*   **The Parquet export on Hugging Face with DuckDB.** Smaller (8 GB) and
    pinnable by commit, but its column layout is not documented here, so it
    needs an adapter into the API's product shape, plus a DuckDB install.
*   **A TypeScript builder.** Would need a second copy of the mapping in
    TypeScript, kept in step by golden vectors, and `tsx` resolvable from the
    repository root.
*   **Reason for Rejection**: The JSONL dump has the API's shape, so the app's
    one Dart mapping reads it directly. The cost is a larger download and a
    longer run, once a quarter.

### Alternative Q: Keep the 5,000-row device-cache cap, with an `in_bundle` flag

*   **Pros**: Bounds the device cache even if a user opens many products.
*   **Cons**: Eviction can remove a product that is also in the bundle, so the
    design would need an extra flag to protect it, and eviction would need an
    access time kept up to date.
*   **Reason for Rejection**: Only products the user opens or scans are stored,
    so growth is bounded by the user's own actions; the cache directory can be
    cleared by the system anyway.

### Alternative R: Staging table or batched commits for the install

*   **Pros**: Readers could see new rows before the install finishes.
*   **Cons**: A staging table needs a swap step. Batched commits need a
    "complete" flag and lose the property that a killed install leaves the old
    state.
*   **Reason for Rejection**: One transaction on its own connection, with WAL,
    keeps readers working on the last committed state and keeps CUJ 9 simple.

--------------------------------------------------------------------------------

## Non-Functional Requirements

### Security and privacy

*   What live requests send, and when, is listed once under
    [Live requests](#live-requests) ("What is sent").
*   "Look up foods online" turns all of it off on that device.
*   The server makes no outbound requests for this feature.
*   The bundle holds public product data only. The device cache records which
    products the user opened or scanned; it stays on the device, is never
    synced or backed up, and Erase all data removes it (the reference database
    is reset and the bundle reinstalled).

### Performance and storage

*   **Reference device:** a mid-range Android phone of the Google Pixel 6a
    class (2022, 6 GB RAM), and an iPhone 12. Device timings below are measured
    on these by hand before release.
*   **Search:** local search returns within 100 ms after the typing pause ends,
    on the reference device. CI guards it with a host-side budget over a
    synthetic 41,000-row index.
*   **Logging:** unchanged. The log-portion screen and the Food Entry save read
    and write only local databases.
*   **Install:** under 5 seconds on the reference Android device, in the
    background. The UI isolate does only one asset read and decodes the header
    line.
*   **Download size:** at most 6 MB compressed; estimated at about 2.5 MB.
*   **Device storage:** the compressed asset (about 2.5 MB) plus
    `food_reference.sqlite` in the cache directory, estimated at 15 to 20 MB with
    the FTS5 index.
*   **Server:** the in-memory bundle, estimated at 20 to 30 MB, loaded on the
    first Open Food Facts request.

### Rollout and rollback

*   The app is unreleased, so there is no staged rollout.
*   Rolling back the app code is a revert. `food_reference.sqlite` is a cache; an
    older build ignores it, or drops and recreates it by its schema-version rule.
*   The `AppDatabase` change in version 61 only drops a cache table. A rolled-back
    build that expects version 60 cannot open a version 61 database, as with any
    Drift schema bump; on a debug device, reinstall.
*   The agent operation change is additive. Old clients that omit `source` keep
    getting USDA results with the same fields, plus new nullable fields.

### Risks

| Risk | Effect | Mitigation |
| :--- | :----- | :--------- |
| Crowdsourced values are wrong. | A user logs wrong nutrition. | The disclaimer on every Open Food Facts food; the plausibility exclusion; the product link so the user can check and correct the source. |
| `search.pl` is legacy and sometimes returns 503. | Online search fails some of the time. | The device's matches stay on screen; the "unavailable" line explains it; Search-a-licious is a Future Improvement. |
| Open Food Facts bans an IP address for heavy use. | Live lookups stop for that device. | The request budget sits below the published limits, nothing retries on its own, and every request carries a User-Agent with a contact email. |
| The JSONL dump's format changes. | The builder fails or drops products. | The builder's report shows exclusions by reason; a refresh is reviewed in its own pull request. |
| The server's first Open Food Facts request loads the bundle synchronously. | The Node event loop, and every request in flight on that process, waits an estimated few hundred milliseconds, once per process. | Measured in the server test. If it becomes a problem, load the bundle at startup, before the server accepts requests. |
| ODbL share-alike for synced Food Entry snapshots. | Unclear obligation for the hosted server. | A lawyer's check before public release (a Non-Goal). |

## Additional Resources

*   Open Food Facts API documentation:
    https://openfoodfacts.github.io/openfoodfacts-server/api/ (rate limits,
    User-Agent rule, staging host, data dumps; read 2026-10-25).
*   Open Food Facts terms of use: https://world.openfoodfacts.org/terms-of-use
    (licences, attribution, accuracy disclaimer).
*   ODbL 1.0 summary and full text:
    https://opendatacommons.org/licenses/odbl/summary/ and
    https://opendatacommons.org/licenses/odbl/1-0/.
*   Open Food Facts data dumps: https://world.openfoodfacts.org/data.
*   Search-a-licious API: https://search.openfoodfacts.org/docs.

## Future Improvements

*   **Search-a-licious.** Move live search to it once Open Food Facts lists it
    as the supported search API. One client method changes.
*   **Kilojoule energy.** Australian and New Zealand labels lead with kJ. If the
    builder's report shows many AU or NZ products dropped for missing
    `energy-kcal_100g`, derive kcal from `energy-kj_100g` (divide by 4.184).
*   **Country-aware live search.** Filter or rank live results by the device's
    region, once the right parameters are confirmed against a working endpoint.
*   **Country packs** for regions outside the launch list, downloaded once on
    Wi-Fi.
*   **More USDA foods,** so generic foods are found offline too. Needs its own
    spec for the USDA data pipeline.
*   **Brand in the Food Entry snapshot,** so logged history shows the brand.
    Changes the Food Entry shape and sync.
*   **Live lookups for agents,** if there is demand, through a hosted mirror of
    the dumps rather than a proxy to Open Food Facts.

--------------------------------------------------------------------------------

## Detailed Implementation Plan

The work lands in three implementation pull requests, in this order, each
green on `pnpm ci:local --changed` on its own. Each links this spec. The
summaries below name the main work; the file entries that follow are the full
list.

1.  **Shared rules and the bundle.** The Dart mapping in the domain layer, the
    `PlatformFoodRecord` fields it needs, the barcode candidate rule in both
    languages with its golden vectors, the builder, the bundle file, the asset
    test and the licence files. **The app's live path is not changed:** the old
    `OpenFoodFactsRepository` and its `_openFoodFacts*` helpers stay as they are
    until pull request 2, so the two mappings exist side by side for one pull
    request.
2.  **The app.** The reference database, the installer, the client, the
    repository and its providers, the picker, the scanner, the log-portion
    screen, the Nutrition Day view, the setting and its screen, the About
    screen, Erase all data, the `AppDatabase` change, and removal of the old
    repository and helpers.
3.  **The server.** The bundle reader, the widened agent operation and MCP tool,
    the contract regeneration and the Dockerfile.

The CONTEXT.md change lands in pull request 2, the first one that changes app
screens. This spec's Status becomes **Current** in pull request 3.

Conventions in this plan:

*   Paths are from the repository root.
*   "Live" and "online" mean the same thing (a request to Open Food Facts).
*   The change date is `modifiedAt` in the bundle line, `modified_at` in
    SQLite, `sourceModifiedAt` on `PlatformFoodRecord`, `FoodPickerItem` and the
    agent response, and `changeDate` on the attribution notice.
*   `origin` values are written `bundle` and `online` in prose and `'bundle'`
    and `'online'` in SQL.
*   CI jobs are named by their `ci-local.mjs` key, with the `ci.yml` job id in
    brackets where it differs: `mobile`, `golden` [`golden_vectors`], `contract`
    [`contract-drift`], `js`, `sync` [`sync-convergence`].

### Target Files to Create/Modify

#### Pull request 1: shared rules and the bundle

##### 1. `apps/mobile/lib/domain/nutrition/open_food_facts.dart` (Create)

*   **Type / Scope**: Dart domain module, pure (imports only `dart:` libraries
    and other files under `apps/mobile/lib/domain/`).
*   **Proposed Changes**:
    *   `OpenFoodFactsMappingResult mapOpenFoodFactsProduct(Map<String, Object?> product, {String? fallbackCode})`.
        `fallbackCode` is used as the code when `product['code']` is absent: the
        live product request passes the requested code; the builder and the live
        search pass none.
    *   `OpenFoodFactsMappingResult` is a sealed class with two cases:
        *   `MappedOpenFoodFactsProduct`: `String code`, `String name`,
            `String? brand`, `bool isLiquid`, `String? servingLabel`,
            `double? servingSize`, `double? packageSize`,
            `Map<NutrientId, String> nutrientText`, `DateTime modifiedAt` (UTC),
            `int? scans`;
        *   `ExcludedOpenFoodFactsProduct`: `OpenFoodFactsExclusion reason`, an
            enum `missingCode`, `missingName`, `missingChangeDate`,
            `implausible`.
    *   The rules are in [The product mapping](#the-product-mapping). Nutrient
        text uses `formatNutrientEntered` (file 2).
    *   `NutrientVector nutrientVectorFromText(Map<NutrientId, String> text)`:
        each entry `(id, entered)` becomes
        `NutrientAmount.complete(value: double.parse(entered), entered: entered, unit: id.defaultUnit)`;
        the vector is built with `NutrientVector.full`, so absent nutrients are
        unknown.
    *   `Map<NutrientId, String> nutrientTextFromVector(NutrientVector vector)`:
        the `entered` text of every complete amount; used when storing a live
        product.
    *   `PlatformFoodRecord toPlatformFoodRecord(MappedOpenFoodFactsProduct product)`,
        setting `foodSource: FoodSource.openFoodFacts`, `brand`,
        `sourceModifiedAt` and `scans`.
    *   `List<String> barcodeCandidates(String raw)`, the rule in
        [Search and barcode rules](#search-and-barcode-rules).
    *   `String? buildFoodSearchMatch(String query)`: the FTS5 match
        expression, or `null` when the query has no parts.
    *   Constants `openFoodFactsFields` (the live `fields` list, as one
        comma-joined string) and `openFoodFactsDisclaimer` (the Goal 7 text),
        and the function `String openFoodFactsProductUrl(String code)`.
    *   The bundle format: `const bundleFormat = 'perennia-open-food-facts-bundle'`
        and `const bundleFormatVersion = 1`;
        `String encodeBundleProductLine(MappedOpenFoodFactsProduct product)`;
        `MappedOpenFoodFactsProduct decodeBundleProductLine(String line)`; and
        `BundleHeader`, with the header's fields (as in
        [The bundle file](#the-bundle-file)), `String toJsonLine()` and
        `static BundleHeader fromJsonLine(String line)`.

##### 2. `apps/mobile/lib/domain/nutrition/nutrition.dart` (Modify)

*   **Type / Scope**: Domain model.
*   **Proposed Changes**:
    *   `PlatformFoodRecord` gains `final String? brand`,
        `final DateTime? sourceModifiedAt` and `final int? scans`, all optional
        and `null` by default.
    *   The private `_formatDerivedValue` becomes the public
        `String formatNutrientEntered(double value)`, with the same body (six
        decimal places, trailing zeros and point removed). Its two callers in
        this file are updated. It is the rule file 1 uses, so there is one copy
        of it.

##### 3. `apps/mobile/tool/open_food_facts_bundle/build_bundle.dart` (Create)

*   **Type / Scope**: Maintainer tool, run with `dart run`.
*   **Proposed Changes**: The steps in [Building the bundle](#building-the-bundle).
    *   Arguments: `--input` (a local `.jsonl.gz` path) and `--dataset-version`
        (`YYYY-MM-DD`).
    *   Constants at the top: the five country tags, the per-country limit
        (10,000) and the size budget (6 MB).
    *   The content hash is computed with `Sha256` from the `cryptography`
        package, already a dependency.
    *   Exits non-zero on a missing or unreadable input, a malformed date, or an
        over-budget result.

##### 4. `apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz` (Create)

*   **Type / Scope**: Generated data, ODbL.
*   **Proposed Changes**: Output of file 3 against the dump current when pull
    request 1 is opened. The pull request description records the dataset
    version and the builder's report.

##### 5. `apps/mobile/assets/seeds/open_food_facts_bundle.LICENSE.md` (Create)

*   **Type / Scope**: Licence notice. Not bundled into the app; the About screen
    names its repository path, and the bundle header carries the licence URLs.
    (`platform_exercises.LICENSE.md` is bundled because the exercise screens
    show no such link; the USDA seed is public domain and has no licence file.)
*   **Proposed Changes**: States that the bundle is a derived database of Open
    Food Facts (`https://world.openfoodfacts.org/`), made available under ODbL
    1.0, with individual contents under DbCL 1.0, and links both licences. It
    names `apps/mobile/tool/open_food_facts_bundle/build_bundle.dart` as the
    method used to derive it, and repeats the disclaimer.

##### 6. `THIRD_PARTY_DATA.md` (Create)

*   **Type / Scope**: Repository-root notice.
*   **Proposed Changes**: One table: each dataset the repository ships (the Open
    Food Facts bundle, the USDA FoodData Central seed, the Platform Library
    exercise data), its file, its licence, the attribution required, and its
    licence file if any. States that the data licences are separate from the
    AGPL-3.0 code licence.

##### 7. `packages/golden-vectors/vectors/m36-barcode-candidates.json` and `packages/golden-vectors/vectors/README.md` (Create; Modify)

*   **Type / Scope**: Golden vector fixture and its documentation.
*   **Proposed Changes**:
    *   Top level: `"name": "m36-barcode-candidates"`,
        `"domain": "barcode-candidates"`, and `"cases"`: a list of
        `{ "name", "input", "expected": [strings] }` (the shape
        `packages/golden-vectors/test/vectors.test.mjs` checks).
    *   Cases: 6 and 18 digits (the boundaries); 5 and 19 digits (not barcodes);
        8 digits; 12 digits; 13 digits not starting with `0`; 13 digits starting
        with `0`; spaces, a tab, a newline and hyphens inside a code; letters;
        the empty string.
    *   The README gains a short section naming the fixture and its two
        runners.

##### 8. `apps/server/src/barcode-candidates.ts` (Create)

*   **Type / Scope**: TypeScript module, pure.
*   **Proposed Changes**: `export function barcodeCandidates(raw: string): string[]`,
    the same rule as file 1.

##### 9. Server golden runner and registration (Create; Modify; Modify)

*   **Files**: `apps/server/test/barcode-candidates.golden.test.mjs` (Create),
    `apps/server/package.json` (Modify),
    `apps/server/test/agent-validation.golden.test.mjs` (Modify).
*   **Proposed Changes**:
    *   The runner loads every fixture whose `domain` is `barcode-candidates`,
        asserts each case against file 8, and asserts at least one case ran.
    *   `package.json`: add the runner to the `test:golden-vectors` script.
    *   `agent-validation.golden.test.mjs`: add `barcode-candidates` to
        `DOMAINS_OWNED_ELSEWHERE`, with a comment naming the runner.

##### 10. Dart golden runner and registration (Create; Modify)

*   **Files**: `apps/mobile/test/domain/barcode_candidates_golden_test.dart`
    (Create), `apps/mobile/test/domain/golden_vector_ownership_test.dart`
    (Modify).
*   **Proposed Changes**:
    *   The runner loads `packages/golden-vectors/vectors/m36-barcode-candidates.json`
        by that file name (the ownership guard requires the owner file to name
        the fixture, as `effect_window_golden_test.dart` does), asserts each
        case against file 1, and asserts at least one case ran.
    *   The ownership table maps `barcode-candidates` to the runner.

##### 11. `apps/mobile/test/domain/open_food_facts_mapping_test.dart` (Create)

*   **Type / Scope**: Dart unit test.
*   **Proposed Changes**:
    *   **Mapping:**
        *   a full product;
        *   only the four core nutrients;
        *   `energy-kcal_value` present without `energy-kcal_100g` (energy
            unknown);
        *   a negative value (unknown);
        *   sodium, cholesterol and caffeine converted to milligrams;
        *   `product_name_en` used when `product_name` is absent;
        *   no name (excluded);
        *   no `last_modified_t` (excluded);
        *   energy 901 kcal, and fat 100.1 g (each excluded as implausible);
        *   `brands` with several entries;
        *   serving and package given as numbers with units, and as text only;
        *   a liquid;
        *   values whose text needs trailing zeros removed;
        *   `fallbackCode` used when `code` is absent.
    *   **Line format:** encode then decode returns the same product; nulls are
        written as `null`; the key order is as specified.
    *   **`buildFoodSearchMatch`:** mixed case, punctuation, more than 8 words,
        typed FTS5 operators (`AND`, `NEAR`, `*`, `:`) searched as text, empty
        and punctuation-only queries.
    *   **`nutrientTextFromVector`:** the inverse of `nutrientVectorFromText` for
        complete amounts.

##### 12. `apps/mobile/test/data/open_food_facts_bundle_asset_test.dart` (Create)

*   **Type / Scope**: Dart test that reads the committed bundle. The builder has
    no separate verify mode.
*   **Proposed Changes**: Fails if any of these holds:
    *   the header's `format` or `formatVersion` differs from `bundleFormat` and
        `bundleFormatVersion`;
    *   `productCount` differs from the number of product lines;
    *   codes are not unique, or not sorted;
    *   a line does not decode with `decodeBundleProductLine`, or has a key not
        in the format;
    *   a nutrient key is not a `NutrientId`;
    *   `contentHash` differs from the SHA-256 of the product lines;
    *   the file is over 6 MB.

    The asset is under `apps/mobile`, so the `mobile` job runs on changes to it.

##### 13. `.github/workflows/ci.yml` and `tools/ci-local.mjs` (Modify)

*   **Type / Scope**: CI configuration, changed together.
*   **Proposed Changes**: `golden` [`golden_vectors`]: add
    `apps/server/src/barcode-candidates.ts` and
    `apps/server/test/barcode-candidates.golden.test.mjs` to its paths. The Dart
    side needs no change: the job's paths already cover
    `apps/mobile/test/domain/**`, and its Dart step runs every test that reads
    `packages/golden-vectors`.

##### 14. `docs/development.md` (Modify)

*   **Type / Scope**: Documentation.
*   **Proposed Changes**: A section "Refreshing the Open Food Facts bundle":
    *   downloading the dump, with its size and that it changes daily;
    *   the builder command and how to read its report;
    *   recording the dataset version and the report in the pull request;
    *   that refreshes are planned at most once a quarter, with an app release,
        each in its own pull request.

#### Pull request 2: the app

##### 15. `apps/mobile/lib/data/local/food_reference_database.dart` and `apps/mobile/lib/data/local/food_reference_database.g.dart` (Create; `.g.dart` generated)

*   **Type / Scope**: Drift database (Dart tables). The generated file is
    committed like `app_database.g.dart`.
*   **Proposed Changes**:
    *   `@DriftDatabase(tables: [ReferenceMeta, OpenFoodFactsProducts])`.
        `class FoodReferenceDatabase extends _$FoodReferenceDatabase`, with
        `schemaVersion = 1`.
    *   `@DataClassName('OpenFoodFactsProductRow')` on `OpenFoodFactsProducts`,
        whose columns are as in
        [Installing the bundle on the device](#installing-the-bundle-on-the-device):
        `id` autoincrement and `code` unique.
    *   `onCreate` calls `m.createAll()`, then creates the FTS5 table and its
        insert, update and delete triggers with `customStatement`. `onUpgrade`
        drops every table and runs `onCreate`.
    *   Factories:
        *   `FoodReferenceDatabase.memory()`, for tests;
        *   `FoodReferenceDatabase.connect(File file)`: the app's connection,
            through `NativeDatabase.createInBackground(file, setup: …)`;
        *   `FoodReferenceDatabase.openInIsolate(File file)`: the installer's
            connection, through `NativeDatabase(file, setup: …)`.

        Every `setup` runs `PRAGMA journal_mode=WAL` and
        `PRAGMA busy_timeout=5000`.
    *   Queries:
        *   `Future<List<OpenFoodFactsProductRow>> searchProducts(String match, int limit)`:
            the FTS5 join and order, with `bm25` ascending.
        *   `Future<List<OpenFoodFactsProductRow>> productsByCodes(List<String> codes)`,
            in the given order.
        *   `Future<void> keepProduct(OpenFoodFactsProductsCompanion row)`:
            insert with `origin = 'online'`. On a conflict on `code`, always set
            `origin = 'online'`, and replace the other values only when
            `excluded.modified_at > modified_at`.
        *   `Future<void> replaceBundle(Iterable<String> productLines, BundleHeader header, {Future<void> Function()? beforeCommitForTesting})`:
            the three install steps in one transaction. Its insert is
            `INSERT … ON CONFLICT(code) DO UPDATE SET <values> WHERE excluded.modified_at > modified_at`
            and never changes `origin`. `beforeCommitForTesting` runs just
            before the transaction commits.
        *   `Future<void> resetAll()`: delete every product row and the
            `bundle_content_hash` key.
        *   `Future<String?> metaValue(String key)` and
            `Future<void> setMeta(String key, String value)`.

##### 16. `apps/mobile/lib/data/open_food_facts/open_food_facts_client.dart` (Create)

*   **Type / Scope**: Repository-layer HTTP client.
*   **Proposed Changes**:
    *   `OpenFoodFactsClient({required http.Client httpClient, Uri? baseUrl, DateTime Function()? clock})`.
        `baseUrl` defaults to `https://world.openfoodfacts.org/`; tests and the
        staging check pass another.
    *   `Future<OpenFoodFactsOutcome> search(String query)` and
        `Future<OpenFoodFactsOutcome> product(String code)`, with the endpoints,
        parameters, timeout and outcomes in [Live requests](#live-requests).
        `product` passes `code` as the mapping's `fallbackCode`.
    *   `OpenFoodFactsOutcome` is a sealed class:
        *   `OpenFoodFactsResults(List<MappedOpenFoodFactsProduct> products)`;
        *   `OpenFoodFactsNotFound()`;
        *   `OpenFoodFactsOffline()`;
        *   `OpenFoodFactsUnavailable(OpenFoodFactsUnavailableReason reason)`,
            where the reason is one of `rateLimited`, `busy`, `httpError`,
            `malformed` and `budgetExceeded`, mapped as in
            [Live requests](#live-requests).
    *   `RequestBudget` (same file): a sliding 60-second window with a capacity,
        and `bool tryAcquire()`. One budget for search (capacity 10), one for
        products (capacity 15).
    *   `const openFoodFactsContactEmail = '<supplied by the maintainer>';` and
        `String perenniaUserAgent()`, returning
        `Perennia/${perenniaAppVersion.split('+').first} ($openFoodFactsContactEmail)`.
        A test in file 37 fails while the constant is not an email address, so
        pull request 2 cannot merge until the maintainer sets it (see
        [Open Questions](#open-questions)).

##### 17. App version constant (Create; Modify; Modify)

*   **Files**: `apps/mobile/lib/data/app_version.dart` (Create),
    `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify),
    `apps/mobile/lib/data/repositories/portable_archive_repository.dart`
    (Modify).
*   **Proposed Changes**:
    *   `app_version.dart`: `const perenniaAppVersion = '0.1.0+1';`, the value
        moved from `PortableArchiveRepository.appVersion`.
    *   `training_repositories.dart`: imports `../app_version.dart`.
        `portable_archive_repository.dart` is a `part` of this library, so the
        import goes here.
    *   `portable_archive_repository.dart`:
        `static const appVersion = perenniaAppVersion;`, so existing callers are
        unchanged.

##### 18. `apps/mobile/lib/data/open_food_facts/open_food_facts_bundle_installer.dart` (Create)

*   **Type / Scope**: Repository-layer service.
*   **Proposed Changes**:
    *   `abstract interface class BundleAssetSource { Future<Uint8List> load(); }`.
        `RootBundleAssetSource` reads
        `assets/seeds/open_food_facts_bundle.ndjson.gz` with `rootBundle.load`.
    *   Constructor:

        ```text
        OpenFoodFactsBundleInstaller({
          required FoodReferenceDatabase database,
          required BundleAssetSource asset,
          File? databaseFile,
          ClientCrashReporter? crashReporter,
        })
        ```

        With `databaseFile` set, the install runs in `Isolate.run`, on a
        `FoodReferenceDatabase.openInIsolate(databaseFile)` connection that it
        closes before returning. Without it (tests with an in-memory database),
        the install runs `replaceBundle` on `database` directly.
    *   `Future<void> ensureInstalled()` runs the steps in
        [Installing the bundle on the device](#installing-the-bundle-on-the-device):
        *   inside the isolate: decode the bytes, then call `replaceBundle`;
        *   a call while an install runs returns the running install's future;
        *   every failure sets `failed` and calls
            `crashReporter?.captureException(error, stackTrace)`; nothing is
            thrown.
    *   `BundleStatus get currentStatus` and `Stream<BundleStatus> watchStatus()`,
        which emits `currentStatus` first and then each change. `BundleStatus`
        is the enum `unknown`, `installing`, `ready` and `failed`.
    *   `Future<BundleHeader?> bundleHeader()` reads the asset's header, or
        returns `null` if it cannot.

##### 19. `apps/mobile/lib/data/repositories/open_food_facts_repository.dart` (Create)

*   **Type / Scope**: Repository: an interface, its Drift implementation, a
    stub, and providers.
*   **Proposed Changes**:
    *   `enum OnlineSearchStatus { ok, noResults, offline, unavailable, disabled }`
        and
        `enum BarcodeLookupOutcome { found, notFound, notABarcode, offline, unavailable, disabled }`.
    *   `abstract interface class OpenFoodFactsRepository` with:
        *   `Future<void> ensureBundleInstalled()`;
        *   `Stream<BundleStatus> watchBundleStatus()`;
        *   `Future<BundleHeader?> bundleHeader()`;
        *   `Future<List<PlatformFoodRecord>> searchLocal(String query, {int limit = 50})`:
            barcode-candidate matches first, then `searchProducts` with
            `buildFoodSearchMatch`, without duplicates;
        *   `Future<({OnlineSearchStatus status, List<PlatformFoodRecord> products})> searchOnline(String query, {required bool allowOnline})`,
            which stores nothing;
        *   `Future<({BarcodeLookupOutcome status, PlatformFoodRecord? product})> lookupBarcode(String raw, {required bool allowOnline})`:
            a stored match is returned with `found` and nothing is sent; a live
            hit is returned at once and kept in the background;
        *   `Future<void> keepOpenedProduct(PlatformFoodRecord record)`, which
            calls `keepProduct` with the record's fields and
            `nutrientTextFromVector`;
        *   `Future<void> resetDeviceData()`: waits for a running install, then
            `resetAll()`, then `ensureBundleInstalled()`.
    *   `DriftOpenFoodFactsRepository implements OpenFoodFactsRepository`:
        *   the app constructor
            `DriftOpenFoodFactsRepository({required Future<File> Function() databaseFile, required OpenFoodFactsClient client, ClientCrashReporter? crashReporter})`
            resolves the file and opens `FoodReferenceDatabase.connect` lazily
            on first use, and builds the installer with that file and
            `RootBundleAssetSource`;
        *   the test constructor
            `DriftOpenFoodFactsRepository.forTesting({required FoodReferenceDatabase database, required OpenFoodFactsClient client, required BundleAssetSource asset})`
            builds the installer with no `databaseFile`;
        *   `Future<void> close()` closes the database.
    *   `StubOpenFoodFactsRepository` (a `const` class): installs nothing, its
        status stream emits `ready`, every search is empty, `searchOnline` and
        `lookupBarcode` return `disabled`, and `bundleHeader()` returns `null`.
    *   Providers:
        *   `openFoodFactsRepositoryProvider = Provider<OpenFoodFactsRepository>`,
            building `DriftOpenFoodFactsRepository` with `databaseFile`
            returning `File(p.join((await getApplicationCacheDirectory()).path, 'food_reference.sqlite'))`,
            `OpenFoodFactsClient(httpClient: http.Client())` and
            `ref.read(clientCrashReporterProvider)`, and calling `close()` on
            dispose;
        *   `bundleStatusProvider = StreamProvider<BundleStatus>`, from
            `watchBundleStatus()`;
        *   `bundleHeaderProvider = FutureProvider<BundleHeader?>`, from
            `bundleHeader()`.

##### 20. `apps/mobile/lib/data/repositories/training_repositories.dart` (Modify)

*   **Type / Scope**: Repository aggregate.
*   **Proposed Changes**: Remove:
    *   the `OpenFoodFactsRepository` class and the `openFoodFacts` field;
    *   the constructor parameters `openFoodFactsBaseUrl`,
        `openFoodFactsHttpClient`, `openFoodFactsMaxCacheEntries` and
        `openFoodFactsClock`;
    *   `defaultOpenFoodFactsMaxCacheEntries`;
    *   every `_openFoodFacts*` helper, including `_openFoodFactsLookupKey`,
        `_openFoodFactsBarcode` and `_openFoodFactsRecordFromCacheRow`.

##### 21. `apps/mobile/lib/data/local/app_database.dart` and `apps/mobile/lib/data/local/app_database.g.dart` (Modify; `.g.dart` regenerated)

*   **Type / Scope**: Drift schema.
*   **Proposed Changes**:
    *   Delete the `OpenFoodFactsCache` table class and remove it from the
        `@DriftDatabase` table list.
    *   Delete `openFoodFactsCacheTable` and its entry in `schemaTableNames`.
    *   Remove the `from < 33` step that creates the table.
    *   Set `schemaVersion` to 61, and add a `from < 61` step running
        `DROP TABLE IF EXISTS open_food_facts_cache`, with a docstring saying why
        no rows are copied.

##### 22. `apps/mobile/lib/features/nutrition/repositories/add_food_repository.dart` (Modify)

*   **Type / Scope**: Feature repository.
*   **Proposed Changes**:
    *   `FoodPickerItem` gains `String? brand`, `DateTime? sourceModifiedAt`,
        `int? scans` and `bool isLiveResult` (default `false`).
    *   `AddFoodRepository` (the interface) gains:
        *   `Future<bool> onlineLookupsEnabled()`;
        *   `Future<({OnlineSearchStatus status, List<FoodPickerItem> items})> searchOnline(String query)`,
            whose items have `isLiveResult: true`;
        *   `Future<({BarcodeLookupOutcome status, FoodPickerItem? item})> lookupBarcode(String raw)`;
        *   `Future<void> keepOpenedProduct(FoodPickerItem item)`.
    *   The implementation's constructor becomes:

        ```text
        RepositoryAddFoodRepository(
          TrainingRepositories repositories, {
          OpenFoodFactsRepository? openFoodFacts,
          Future<bool> Function()? onlineLookupsEnabled,
        })
        ```

        The existing one-argument calls keep compiling. With no `openFoodFacts`,
        the Open Food Facts filter returns no items and the online methods
        return `disabled`. With no `onlineLookupsEnabled`, lookups count as on.
    *   The provider passes `ref.watch(openFoodFactsRepositoryProvider)`, and an
        `onlineLookupsEnabled` that reads
        `(await ref.read(settingsControllerProvider.future)).onlineFoodLookups`.
    *   The `openFoodFacts` filter's `search` calls `searchLocal`. The new
        methods pass the setting as `allowOnline`.

##### 23. `apps/mobile/lib/features/nutrition/controllers/add_food_controller.dart` (Modify)

*   **Type / Scope**: Riverpod controller.
*   **Proposed Changes**:
    *   **State.** `AddFoodPickerState` keeps `results` (the device's matches,
        for every filter) and `barcodeLookupStatus`, and gains:
        *   `List<FoodPickerItem> onlineResults`;
        *   `OnlinePickerStatus onlineStatus`, a new enum in this file:
            `idle`, `loading`, `ok`, `noResults`, `offline`, `unavailable`;
        *   `bool onlineLookupsEnabled`;
        *   `BundleStatus bundleStatus`.
    *   **`BarcodeLookupStatus`** gains `unavailable` and `disabled`.
    *   **`build`** reads `onlineLookupsEnabled()` once, and listens to
        `settingsControllerProvider` (updating `onlineLookupsEnabled`) and to
        `bundleStatusProvider` (updating `bundleStatus`, and re-running the local
        search when it becomes `ready`).
    *   **`setQuery`** keeps the 300 ms local search, and resets `onlineResults`
        to empty and `onlineStatus` to `idle` when the query changes.
    *   **`Future<FoodPickerItem?> submitQuery(String query)`** (it returned
        `Future<void>`): cancels the pending debounce and runs the local search
        at once. Then, in the Open Food Facts filter, it follows
        [Submitting the query](#the-picker-the-scanner-and-the-log-portion-screen):
        *   it returns the item to open: a stored candidate match, or a live
            barcode hit;
        *   it sets `barcodeLookupStatus` for a barcode miss;
        *   it sets `onlineStatus` and `onlineResults` for a live search,
            applying the Goal 4 replacement in `results`.

        It sets `onlineStatus: loading` on the current `AsyncData` state and
        never emits `AsyncLoading`. In other filters it behaves as before and
        returns `null`.
    *   **`lookupBarcode`** (scan) maps `BarcodeLookupOutcome` to
        `BarcodeLookupStatus`:
        *   `found` returns the item;
        *   `notFound` and `notABarcode` give `notFound`;
        *   `offline` gives `needsNetwork`;
        *   `unavailable` gives `unavailable`;
        *   `disabled` gives `disabled`.
    *   **`void openItem(FoodPickerItem item)`**: when `item.isLiveResult` is
        true, calls `unawaited(repository.keepOpenedProduct(item))`.
    *   The `brandedSearchNeedsNetwork` flag is removed.

##### 24. `apps/mobile/lib/features/nutrition/widgets/add_food_picker.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**:
    *   **Layout.** The groups, the online slot with its precedence, the bundle
        line, the empty-query line and the barcode lines, as in
        [The picker, the scanner and the log-portion screen](#the-picker-the-scanner-and-the-log-portion-screen).
    *   **Keys** (on `AddFoodPicker`):
        *   `onlineSearchRowKey`, `onlineGroupKey`, `onlineStatusLineKey`;
        *   `bundleStatusLineKey`, `emptyQueryLineKey`, `barcodeStatusLineKey`.
    *   **Rows.** Result rows show the brand as a secondary line.
    *   **Opening.** `onSubmitted` awaits `submitQuery`, and opens the
        log-portion screen for a returned item through the same path the scan
        uses. Opening any item calls the controller's `openItem` first.
    *   **Style.** Text and colours come from `context.textStyles` and
        `context.colors`; no new tokens.
    *   The two "needs network the first time" messages are removed.

##### 25. `apps/mobile/lib/features/nutrition/widgets/nutrition_attribution.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**:
    *   `OpenFoodFactsAttributionNotice` gains optional `String? code` and
        `DateTime? changeDate`, and the compact and full forms in
        [The picker, the scanner and the log-portion screen](#the-picker-the-scanner-and-the-log-portion-screen).
    *   `NutritionAttributionKeys` gains `openFoodFactsProductLink`,
        `openFoodFactsDisclaimer` and `openFoodFactsChangeDate`.
    *   Add `openFoodFactsDbclUrl = 'https://opendatacommons.org/licenses/dbcl/1-0/'`
        next to the existing `openFoodFactsSourceUrl` and `openFoodFactsOdblUrl`.

##### 26. `apps/mobile/lib/features/nutrition/widgets/log_portion_screen.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**:
    *   Under the name, show the brand when present.
    *   Replace the compact `OpenFoodFactsAttributionNotice` with the full form
        for every food whose source is `FoodSource.openFoodFacts`, passing the
        food's id as `code` and `sourceModifiedAt` as `changeDate`.

##### 27. `apps/mobile/lib/features/nutrition/widgets/nutrition_day_view.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**:
    *   The `showImportedBadge` condition becomes
        `foodSource != null && (entry.isImported || foodSource == FoodSource.openFoodFacts)`.
    *   Imported entries keep their current badge and
        `NutritionDayView.importedEntryBadgeKey`.
    *   An Open Food Facts entry that is not imported shows
        `FoodSourceBadge(source: FoodSource.openFoodFacts, showLicense: false)`.
        That widget carries its own key,
        `NutritionAttributionKeys.foodSourceBadge(FoodSource.openFoodFacts)`.

##### 28. `apps/mobile/lib/features/settings/repositories/settings_repository.dart` (Modify)

*   **Type / Scope**: Settings model and controller.
*   **Proposed Changes**:
    *   `AppSettings` gains `final bool onlineFoodLookups` (constructor default
        `true`), read and written in `fromJson`, `toJson` and `copyWith`, and
        included in `==` and `hashCode`.
    *   `SplitSettingsRepository` keeps it in the device-level half, which it
        saves through `FileSettingsRepository`; it is never written to the
        synced account row.
    *   `SettingsController` gains `Future<void> setOnlineFoodLookups(bool enabled)`,
        following `setThemePreference`.

##### 29. `apps/mobile/lib/features/settings/widgets/food_data_settings_screen.dart` (Create)

*   **Type / Scope**: Widget, a Settings sub-screen. The Settings hub holds no
    inline controls.
*   **Proposed Changes**: `FoodDataSettingsScreen` (a `ConsumerWidget`), built
    like `PrivacySettingsScreen`:
    *   `SettingsSubScreen(title: 'Food data')`, containing one `SwitchListTile`;
    *   the switch has key `onlineFoodLookupsSwitchKey = Key('settings.foodData.onlineLookups')`,
        title "Look up foods online", and subtitle "Sends your search text or
        barcode to Open Food Facts. The offline food list works without it.";
    *   it calls `setOnlineFoodLookups`.

##### 30. `apps/mobile/lib/features/settings/widgets/settings_screen.dart` (Modify)

*   **Type / Scope**: Widget, the Settings hub.
*   **Proposed Changes**:
    *   Add `export 'food_data_settings_screen.dart';` with the other exports.
    *   Add `static const foodDataTileKey = Key('settings.hub.foodData');`.
    *   In the "Data & privacy" group, after "Privacy & security", add a
        `SettingsNavTile`:
        *   key `foodDataTileKey`, icon `Icons.restaurant_outlined`;
        *   title "Food data";
        *   subtitle "Online lookups on" or "Online lookups off";
        *   it opens `FoodDataSettingsScreen`.

##### 31. `apps/mobile/lib/features/settings/widgets/about_screen.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**:
    *   `AboutScreen` and `_NutritionCredits` become `ConsumerWidget`s.
        `_NutritionCredits` reads `bundleHeaderProvider`.
    *   Replace the Open Food Facts paragraph and the offline paragraph with the
        texts in
        [The picker, the scanner and the log-portion screen](#the-picker-the-scanner-and-the-log-portion-screen):
        *   the parenthesis is left out while loading, on `null` and on error;
        *   the paragraph is followed by the source, ODbL and DbCL links.

##### 32. `apps/mobile/lib/features/settings/widgets/data_management_screen.dart` (Modify)

*   **Type / Scope**: Widget.
*   **Proposed Changes**:
    *   **Handler.** The default Erase all data handler calls
        `trainingRepositories.eraseAllData()` and then
        `ref.read(openFoodFactsRepositoryProvider).resetDeviceData()`.
    *   **Dialog.** The confirmation dialog's text gains a final sentence: "Open
        Food Facts products you opened or scanned are cleared from this device
        too, and undo does not bring them back."

##### 33. `apps/mobile/lib/app.dart` (Modify)

*   **Type / Scope**: App shell.
*   **Proposed Changes**:
    *   In the existing first-frame callback in `_PerenniaAppState.initState`,
        call `unawaited(ref.read(openFoodFactsRepositoryProvider).ensureBundleInstalled())`.
    *   `PerenniaRoot` gains an optional `OpenFoodFactsRepository? openFoodFactsRepository`.
        When it is set, it overrides `openFoodFactsRepositoryProvider`. When it
        is not set and `homeRepository` is set (the app-shell harness), the
        provider is overridden with `const StubOpenFoodFactsRepository()`. This
        follows the existing Up-next and template-picker defaults.

##### 34. `apps/mobile/pubspec.yaml` (Modify)

*   **Type / Scope**: Build configuration.
*   **Proposed Changes**: Add `assets/seeds/open_food_facts_bundle.ndjson.gz` to
    `flutter.assets`.

##### 35. `.github/workflows/ci.yml` and `tools/ci-local.mjs` (Modify)

*   **Type / Scope**: CI configuration, changed together.
*   **Proposed Changes**: In the `mobile` job, extend the generated-code diff
    check to `apps/mobile/lib/data/local/food_reference_database.g.dart`.

##### 36. `CONTEXT.md` and `ARCHITECTURE.md` (Modify)

*   **Type / Scope**: Vocabulary and documentation.
*   **Proposed Changes**:
    *   `CONTEXT.md` gets the three changes in [Vocabulary](#vocabulary).
    *   `ARCHITECTURE.md` gains one paragraph in "The app": reference data that
        can be rebuilt (the Open Food Facts bundle and the device cache) lives in
        a separate database file in the cache directory, outside sync and
        backups.

##### 37. App tests (Create and Modify)

*   **Type / Scope**: Tests. Repository tests run against real SQLite (in memory
    unless stated otherwise).
*   **New test files:**
    *   `apps/mobile/test/data/food_reference_database_test.dart` (Create):
        *   FTS5 is available; the match and order rules hold.
        *   `keepProduct`: keeps the stored values when the incoming copy is
            older, takes the incoming values when it is newer, and always sets
            `origin = online`.
        *   An install keeps a newer `online` row's values, replaces an older
            one's values, and leaves both `online`.
        *   A reinstall deletes only `bundle` rows. A kept product that is absent
            from a new bundle survives the reinstall.
        *   `resetAll` followed by an install leaves the full bundle and no
            `online` rows, including for a bundled product that had been kept.
        *   A failure inside `replaceBundle` rolls back to the previous state
            (this simulates a kill, CUJ 9).
        *   `AppDatabase.schemaTableNames` contains no Open Food Facts table.
    *   `apps/mobile/test/data/food_reference_install_concurrency_test.dart`
        (Create), on real files in a temporary directory, with
        `beforeCommitForTesting` holding the install transaction open:
        *   a read on the app's connection returns the committed state within
            100 ms;
        *   a Food Entry save on an `AppDatabase` file completes;
        *   `keepProduct` on the app's connection completes after the install
            commits.
    *   `apps/mobile/test/data/open_food_facts_client_test.dart` (Create), with
        `MockClient`:
        *   the exact User-Agent, URLs and parameters;
        *   v3.6 found and not-found bodies;
        *   404, 429, 503, another non-2xx, timeout and malformed bodies, each
            with its outcome and reason;
        *   the 11th search and the 16th product request in 60 seconds are not
            sent (`budgetExceeded`);
        *   `openFoodFactsContactEmail` matches
            `^[^<>\s@]+@[^<>\s@]+\.[^<>\s@]+$`.
    *   `apps/mobile/test/data/open_food_facts_bundle_installer_test.dart`
        (Create):
        *   installs from a small fixture bundle;
        *   skips when the hash matches, and reinstalls when it differs;
        *   reports `failed`, without throwing, on a corrupt file, on an unknown
            `formatVersion` and when the asset source throws;
        *   a second `ensureInstalled` during an install returns the same future;
        *   a new status listener receives the current status first.
    *   `apps/mobile/test/data/open_food_facts_repository_test.dart` (Create):
        *   barcode candidates come first in local search;
        *   live search stores nothing;
        *   `keepOpenedProduct` and a live barcode hit store the product as
            `online`;
        *   `resetDeviceData` leaves the full bundle and an empty device cache;
        *   nothing is sent when `allowOnline` is false.
    *   `apps/mobile/test/data/open_food_facts_cache_drop_migration_test.dart`
        (Create): a version-60 database with rows in `open_food_facts_cache`
        opens at 61 without the table and with every other table intact.
    *   `apps/mobile/test/features/settings/food_data_settings_screen_test.dart`
        (Create): the switch reads and writes `onlineFoodLookups`, and
        `meetsGuideline` passes for tap target size and text contrast in both
        themes.
*   **Existing tests to change:**
    *   `apps/mobile/test/features/nutrition/add_food_repository_test.dart`
        (Modify):
        *   Delete the tests that cover the old cache, which this spec removes:
            "looks up branded Open Food Facts names through search and caches
            them", "Open Food Facts 404 misses write no cache row and do not
            throw", "Open Food Facts non-2xx misses throw without poisoning the
            cache and retry", "Open Food Facts product status zero is a
            cache-free miss", "Open Food Facts branded search misses on empty or
            unparseable products", "Open Food Facts malformed JSON throws and
            writes no cache row", "Open Food Facts cache evicts least-recently-used
            rows over its bound", and "Open Food Facts Food Entry snapshot stays
            immutable after cache eviction and source change".
        *   Their live-request behaviour is now covered by
            `open_food_facts_client_test.dart` and
            `open_food_facts_repository_test.dart`.
        *   Add tests that the Open Food Facts filter calls `searchLocal`, and
            that the setting is passed as `allowOnline`, using
            `RepositoryAddFoodRepository(repositories, openFoodFacts: …, onlineLookupsEnabled: …)`.
    *   `apps/mobile/test/features/nutrition/add_food_picker_test.dart` (Modify):
        *   The five `AddFoodRepository` fakes implement the four new methods.
        *   The barcode harness's product body gains `last_modified_t`, and its
            requests target the v3.6 path.
        *   New cases:
            *   no request while typing;
            *   the online search row and the keyboard's search action each send
                one request;
            *   groups with no duplicate barcode, and the Goal 4 replacement;
            *   every bundle line and online-slot state, in the stated
                precedence;
            *   the empty-query line;
            *   a typed barcode opens the log-portion screen;
            *   the device's matches stay visible while a live request runs;
            *   opening a live item calls `keepOpenedProduct`;
            *   `meetsGuideline` for tap target size and text contrast on the new
                controls, in both themes.
    *   `apps/mobile/test/features/nutrition/log_portion_screen_test.dart`
        (Modify):
        *   brand, product link, disclaimer and date for an Open Food Facts
            food;
        *   link and disclaimer without a date for a Recent item;
        *   none of them for USDA;
        *   `meetsGuideline` for tap target size and text contrast on the
            attribution block, in both themes.
    *   `apps/mobile/test/features/nutrition/nutrition_day_view_test.dart`
        (Modify):
        *   its three `AddFoodRepository` fakes implement the new methods;
        *   the test "barcode scan opens Log Portion …" stubs `lookupBarcode`
            instead of `search`;
        *   a new case shows the badge without the licence label on an Open
            Food Facts entry.
    *   `apps/mobile/test/features/nutrition/nutrition_repository_test.dart`
        (Modify): the test "deletes Open Food Facts Food Entry as a tombstone
        without cache tombstone" drops its cache-table insert and its assertions
        about `open_food_facts_cache`. Its Food Entry tombstone assertions stay.
    *   `apps/mobile/test/features/sync/sync_repository_test.dart` (Modify):
        the test "syncs Open Food Facts Food Entry snapshots without
        redistributing cache rows" drops its cache-table insert and the two
        cache-table assertions. Its snapshot-sync assertions stay; the device
        cache's absence from sync is asserted in
        `food_reference_database_test.dart`.
    *   Three migration tests change their expected `schemaVersion` from 60 to
        61:
        *   `apps/mobile/test/data/routine_plan_migration_test.dart`;
        *   `apps/mobile/test/data/workout_template_migration_test.dart`;
        *   `apps/mobile/test/data/workout_template_group_migration_test.dart`.
    *   `apps/mobile/test/data/erase_all_data_test.dart` (Modify): remove the
        `AppDatabase.openFoodFactsCacheTable` entry from `_keptTables`, with its
        comment.
    *   `apps/mobile/test/features/settings/split_settings_repository_test.dart`
        (Modify): `onlineFoodLookups` is saved in the device file and never in
        the synced account row.
    *   `apps/mobile/test/features/settings/settings_screen_test.dart` (Modify,
        where `DataManagementScreen` is already tested):
        *   the hub shows the Food data tile with its subtitle and opens the
            sub-screen;
        *   the default Erase all data handler calls `resetDeviceData` after
            `eraseAllData`;
        *   the confirmation dialog shows the new sentence.
    *   `apps/mobile/test/app_shell_test.dart` (Modify): no change is needed in
        its call sites, because `PerenniaRoot` stubs the repository when
        `homeRepository` is set. One new case asserts that pumping the app with
        a real repository, whose cache directory cannot be resolved, shows no
        error and leaves the status `failed`.
    *   `apps/mobile/test/performance/performance_budgets_test.dart`,
        `apps/mobile/test/performance/performance_budget_thresholds.dart` and
        `apps/mobile/test/performance/README.md` (Modify): a 41,000-row
        synthetic index; a two-word prefix search completes under
        `openFoodFactsLocalSearchBudget` (100 ms) on the host; the README gains
        its row.

#### Pull request 3: the server

##### 38. `apps/server/src/open-food-facts-bundle.ts` (Create)

*   **Type / Scope**: TypeScript module.
*   **Proposed Changes**:
    *   `export function loadOpenFoodFactsBundle(file: URL): OpenFoodFactsBundle`
        reads the file synchronously (`readFileSync`, `gunzipSync`) and parses
        it. A read or parse failure throws `OpenFoodFactsBundleUnavailableError`.
    *   `export function getOpenFoodFactsBundle(): OpenFoodFactsBundle` calls the
        loader once, with
        `new URL("../../mobile/assets/seeds/open_food_facts_bundle.ndjson.gz", import.meta.url)`,
        and caches the result for the life of the process.
    *   `export function setOpenFoodFactsBundleLoaderForTesting(loader: (() => OpenFoodFactsBundle) | null): void`
        replaces the loader and clears the cache, for the 503 test.
    *   `OpenFoodFactsBundle` has `header`, `byCode: Map<string, BundleProduct>`
        and `products: BundleProduct[]`, with each product's normalized words
        precomputed.
    *   `export function searchBundle(bundle: OpenFoodFactsBundle, query: string | undefined, limit: number): BundleProduct[]`,
        with the rules in [Agent surface](#agent-surface), using
        `barcodeCandidates` from file 8. An undefined query returns `[]`.
    *   `export const OPEN_FOOD_FACTS_DISCLAIMER`, the Goal 7 text.

##### 39. `apps/server/src/agent-foods.ts` (Modify)

*   **Type / Scope**: Agent route definitions and handler logic.
*   **Proposed Changes**:
    *   `AgentPlatformFoodSourceSchema` becomes `z.enum(["usda", "openFoodFacts"])`.
    *   `AgentPlatformFoodSchema` gains `brand`, `sourceModifiedAt` (ISO-8601,
        UTC) and `productUrl`, all nullable.
    *   `AgentPlatformFoodAttributionSchema` gains `disclaimer`, nullable.
    *   The `search` parameter's description and the route summary change to
        the texts in [Agent surface](#agent-surface).
    *   The route's 503 response schema becomes
        `z.union([AgentApiKeyUnavailableResponseSchema, AgentFoodsUnavailableResponseSchema])`.
    *   `searchAgentPlatformFoods({ search, source = "usda", limit })` stays
        synchronous, and `source` is optional, so the existing calls such as
        `searchAgentPlatformFoods({ limit: 20 })` keep working.
        *   The USDA branch is unchanged, except that the new fields are `null`.
        *   The Open Food Facts branch calls `searchBundle` on
            `getOpenFoodFactsBundle()`, and builds each food's `nutrientsPer100`
            with `nutrientVectorStorage`.
        *   It fills `attribution` from the bundle header: `source`,
            `datasetVersion`, `sourceName`, `sourceUrl`, `licenseName` and
            `attributionText`, with `disclaimer` set to
            `OPEN_FOOD_FACTS_DISCLAIMER`.
    *   The comment block above the platform search is rewritten to describe the
        bundle and the decision not to call Open Food Facts from the server.

##### 40. `apps/server/src/app.ts` and `apps/server/src/agent-mcp.ts` (Modify)

*   **Type / Scope**: Server wiring.
*   **Proposed Changes**:
    *   Both call sites of `searchAgentPlatformFoods` pass `source: query.source`
        next to `search` and `limit`: the REST handler for
        `agentFoodPlatformSearchRoute` in `app.ts`, and the
        `agent_search_platform_foods` tool in `agent-mcp.ts`.
    *   On `OpenFoodFactsBundleUnavailableError`:
        *   the REST handler returns 503 with
            `AgentFoodsUnavailableResponseSchema`
            (`code: "agent_foods_unavailable"`, and the message in
            [Agent surface](#agent-surface));
        *   the MCP tool returns the same body through `errorResult`.
    *   The tool's description says it covers USDA and the Open Food Facts
        bundle. No new dependencies are injected.

##### 41. Server tests (Create and Modify)

*   **Type / Scope**: Node tests.
*   **Proposed Changes**:
    *   `apps/server/test/open-food-facts-bundle.test.mjs` (Create):
        *   reads the committed bundle;
        *   the header's `format` and `formatVersion` equal the values the app's
            asset test checks;
        *   for a sample of barcodes, the search returns the same name, values,
            sizes, brand and change date as their decoded lines;
        *   the name search rules: prefixes, diacritics, the 8-part limit,
            barcode candidates first, and the order;
        *   it prints the load time in the test output.
    *   `apps/server/test/agent-foods.test.mjs` (Modify):
        *   `searchAgentPlatformFoods({ limit: 20 })` still returns USDA with
            unchanged values, plus the new null fields;
        *   Open Food Facts by name and by barcode through `search`;
        *   no `search`, or one with no word parts and no candidates, returns
            empty `foods`;
        *   the nutrient vector includes every id.
    *   `apps/server/test/agent-foods-routes.test.mjs` (Modify): the REST
        responses for Open Food Facts, and a 503 when
        `setOpenFoodFactsBundleLoaderForTesting` installs a loader that throws.
    *   `apps/server/test/agent-mcp.test.mjs` (Modify):
        `agent_search_platform_foods` returns the same body as REST for the same
        input, including the error for an unreadable bundle.

##### 42. `Dockerfile` (Modify)

*   **Type / Scope**: Container build.
*   **Proposed Changes**: In the `runtime` stage, before
    `WORKDIR /app/apps/server`, add
    `COPY apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz /app/apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz`.

##### 43. `.github/workflows/ci.yml` and `tools/ci-local.mjs` (Modify)

*   **Type / Scope**: CI configuration, changed together.
*   **Proposed Changes**: Add `apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz`
    to the `js` job's paths (`JS_PATHS`), because the server tests read it.

##### 44. Generated contract files (Modify, generated)

*   **Type / Scope**: Generated by `corepack pnpm --filter @perennia/contract generate`.
*   **Proposed Changes**: Regenerates:
    *   `packages/contract/openapi.json`;
    *   `packages/contract/src/agent-client.ts`;
    *   `apps/mobile/lib/api/perennia_api_client.dart`;
    *   the agent command map, the generated table in
        `agent-skills/perennia/references/api-operations.md`.

##### 45. `agent-skills/perennia/references/api-operations.md` and `agent-skills/perennia/SKILL.md` (Modify)

*   **Type / Scope**: Agent documentation (hand-written parts).
*   **Proposed Changes**:
    *   The "Food Library Reads and Writes" prose describes
        `source=openFoodFacts`: that `search` takes a name or a barcode, that
        only the bundle is searched, and the attribution and disclaimer to show.
    *   `SKILL.md` gains an example next to the existing
        `search-platform-foods --query search=chicken`:
        `search-platform-foods --query source=openFoodFacts --query search=<code>`.

##### 46. `docs/designs/open-food-facts.md` and `docs/designs/SITEMAP.md` (Modify)

*   **Type / Scope**: This spec.
*   **Proposed Changes**: Status set to **Current**, and its SITEMAP row updated
    to match.

### Verification Plan

*   **Gate:** `pnpm ci:local --changed` green for each pull request. These jobs
    run, selected by the paths each pull request changes, and must pass:
    *   **Pull request 1:**
        *   `mobile`: the mapping, asset and golden tests;
        *   `golden` [`golden_vectors`]: both runners execute the new fixture;
        *   `js`, `contract` [`contract-drift`] and `sync`
            [`sync-convergence`]: selected because `apps/server/**` changes, and
            expected to pass with no other change.
    *   **Pull request 2:**
        *   `mobile`: the codegen diff checks for both databases,
            `flutter analyze`, the performance budgets and `flutter test`;
        *   `golden`: selected because `apps/mobile/test/domain/**` and
            `apps/mobile/lib/domain/**` change.
    *   **Pull request 3:**
        *   `js`;
        *   `contract`: the drift check shows the expected contract diff and
            nothing else;
        *   `golden`: selected because `apps/server/**` changes;
        *   `sync`: no change expected; it confirms that Food Entry snapshots
            with `openFoodFacts` still sync;
        *   `mobile`: selected by the regenerated Dart API client.
*   **Unit and repository tests:** as listed in files 11, 12, 37 and 41.
*   **Golden vectors:** `m36-barcode-candidates.json`, run by Dart and
    TypeScript.
*   **Kill and reopen:** the `replaceBundle` rollback test (it simulates CUJ 9),
    and `food_reference_install_concurrency_test.dart` for reads and saves
    during an install. The existing kill-and-reopen mid-workout tests are
    repository-level and do not involve the installer; they must stay green.
*   **Accessibility:** the `meetsGuideline` checks listed in file 37, for the
    picker, the log-portion attribution block and the Food data screen, in both
    themes.
*   **By hand, before release:**
    *   **On the reference devices:** install time of the real bundle (under 5
        seconds on Android), local search latency (under 100 ms), the app
        download size increase (under 6 MB), and each of CUJs 1 to 6 under the
        network condition its Given states.
    *   **Against the Open Food Facts staging host**
        (`https://world.openfoodfacts.net`, basic auth `off`/`off`, passed
        through the client's `baseUrl`): one search, one found product and one
        missing product.
    *   **An agent session** running CUJ 7 through REST and through MCP,
        comparing the returned record with that barcode's decoded line in the
        bundle of the same dataset version.

--------------------------------------------------------------------------------

<!-- Provenance: Indicates initial structural drafting via EGM. -->

*Drafted with EGM*
