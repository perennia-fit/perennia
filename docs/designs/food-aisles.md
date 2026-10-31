# Food Aisles

*   **Author:** Leonardo Pinheiro
*   **Status:** In Review
*   **Date:** 2026-10-31 (first draft 2026-10-30; revised after review, and again for the definitions experiment)

--------------------------------------------------------------------------------

## Overview

The add-food picker is where a user finds a **Food** to log into a **Meal**.
Many of its Foods are **Platform Foods** from the Open Food Facts bundle, about
41,700 packaged products shipped with the app. These terms, and **Food
Source**, **Food Entry** and **Portion**, are defined in
[CONTEXT.md](../../CONTEXT.md). How the app, the server and the agent surface
fit together is in [ARCHITECTURE.md](../../ARCHITECTURE.md). The rules every
spec must keep are in [AGENTS.md](../../AGENTS.md), and the UI tokens are in
[DESIGN.md](../../DESIGN.md).

[Unified Food Search](unified-food-search.md) (phase 1) makes the picker one
search over every source and shows the user's own Foods before they type. A
new user has no Foods of their own, so they see a search box and a scan
button. This spec is phase 2. It gives every bundled product an **Aisle**, a
grouping that matches how people shop ("Dairy & eggs", "Snacks", "Drinks").
The picker then lists the Aisles before the user types, and tapping one shows
its products, the most scanned first.

The bundle carries no Aisle today, and Open Food Facts has none to copy.
Open Food Facts category tags exist for about 84% of bundled products, but they
are a deep, contributor-written hierarchy, not a short shopping list. Open Food
Facts' food groups (`food_groups_tags`, such as "sugary snacks") are
nutrition-science groups. So this spec also defines a **labelling pipeline**
that runs on a maintainer's machine when the bundle is built. It never runs on
the device, on the server or in CI:

1.  A local **decision model**, Clef, served by Ollama, picks one Aisle per
    product from its name, brand and Open Food Facts category tags. It returns
    a confidence for its choice. Clef alone decides every product; there are
    no hand-written tag rules.
2.  The **Aisle definitions** are the one statement of what belongs where.
    Each Aisle's description is a complete, positive definition that names the
    boundary foods it owns (canned fish is named under Meat & seafood and
    nowhere else). The same descriptions are Clef's criteria and the labelling
    guide a person follows, so the model and the person work from one text.
3.  A **reference set** of products labelled by a person measures the result.
    Part of it is held out: the definitions are tuned on one part and checked
    in CI on the other, and CI fails when the committed labels fall below the
    bar.

The model's outputs are committed, so a bundle build is reproducible from the
dump and the committed files, with no model.

This spec amends [Open Food Facts Integration](open-food-facts.md) (the bundle
file, the builder, the reference database, "One product, one row", and the
agent surface) and [Unified Food Search](unified-food-search.md) (the picker's
blank-query views; its Future Improvements already point to this spec, and
[Alternative A](#alternative-a-map-open-food-facts-tags-to-aisles-with-no-model)
says why this spec labels every product with the model rather than mapping
tags first). Everything else in both stands.

Terms used below:

*   **Aisle (new)**: one of a fixed list of consumer-facing groups of Platform
    Foods. It is defined under [Vocabulary](#vocabulary). It is unrelated to
    the exercise **Category** in CONTEXT.md, and the term "Aisle" is used to
    keep the two apart.
*   **Open Food Facts tags**: the `en:` tags of a product's
    `categories_hierarchy` in the Open Food Facts data, such as `en:snacks`,
    `en:chips-and-fries`, `en:crisps`, from general to specific, parents
    included, with the `en:` prefix kept. Open Food Facts writes every category
    it recognises as an `en:` id whatever the product's language. A tag it does
    not recognise keeps its own language prefix (such as `fr:`) and is ignored
    everywhere in this spec.
*   **Decision model**: a model that answers a fixed-choice question about a
    given state with a probability per option, rather than generating text.
    Clef is Cloudflare's decision model. The pilot ran it as Clef `latest`:
    27 billion parameters, quantised to Q4_K_M (a llama.cpp weight format that
    stores each weight in about 4 to 5 bits), about 20 GB in memory. Ollama
    serves decision models at `POST /v1/systemone`; the request and response
    are shown in [The question asked of the model](#the-question-asked-of-the-model).
*   **Label**: the decision model's answer for one product (its choice and
    confidence), as committed in the labels file.
*   **Dump**, **builder**: as in
    [Open Food Facts Integration § Building the bundle](open-food-facts.md#building-the-bundle).
    **Bundle**, **device cache**: as in
    [Open Food Facts Integration § Overview](open-food-facts.md#overview).
*   **Launch countries**: the five countries the builder takes products from,
    listed in `launchCountries` in
    `apps/mobile/tool/open_food_facts_bundle/build_bundle.dart`: Australia,
    the United States, the United Kingdom, Canada and New Zealand.

### The pilot

A pilot on 2026-10-30 established the numbers this spec relies on. It used 300
products drawn at random from the bundle (seed 7), the taxonomy in
[The Aisles](#the-aisles) with the pilot's descriptions, and Clef `latest` on a
24 GB consumer GPU, with Ollama 0.35.1. An AI assistant labelled each product
blind from its name and brand, before reading any model output. A person did
not label them, so the pilot's agreement figures are a check on the approach,
not a measure of quality. The reference set in this spec is that measure. The
pilot's scripts and data were not committed.

**What was counted.** The AI labeller marked 25 of the 300 products "unsure":
it could not place them from the name and brand alone (for example "NUTRI
GRAIN" with no brand context, or "Coffee Enhancer"). They are left out of every
figure below, so the pilot did not measure products that truly have no Aisle.
That leaves 275 counted products, of which 233 have Open Food Facts tags (252
of all 300 do). The figures count Clef's `other` answer as a disagreement; it
gave one, in 600 answers.

| | Name and brand only | Name, brand and Open Food Facts tags |
| :-- | :-- | :-- |
| Agreement, all 275 counted products, no threshold | 244 of 275 (88.7%) | 257 of 275 (93.5%) |
| Agreement, the 233 counted products with tags | 207 of 233 (88.8%) | 220 of 233 (94.4%) |
| Products kept at confidence ≥ 0.6, and their agreement | 222 of 275 kept (81%); 211 of 222 agree (95.0%) | 241 of 275 kept (88%); 233 of 241 agree (96.7%) |
| Products below confidence 0.6, and their agreement | 52; 33 agree (63%) | 34; 24 agree (71%) |
| Products kept at confidence ≥ 0.9, and their agreement | 96 kept (35%); 95 agree (99.0%) | 127 kept (46%); 123 agree (96.9%) |
| Time per product (median, p95) | 0.81 s, 0.98 s | 0.86 s, 1.05 s |

*   **Runs.** Each setup ran once: 300 requests each, 600 in all, and none
    failed. Whether a repeated run gives the same answers was not measured.
    Builds never depend on it, because labels are committed.
*   **Effect of tags.** Compared with name and brand only, tags turned 15
    disagreements into agreements and 2 agreements into disagreements, a net
    gain of 13 (244 to 257). The 42 counted products without tags agreed in 37
    cases in both setups. Tags added about 0.05 s per product, about 6%.
*   **The unsure products.** With tags, Clef gave 13 of the 25 an Aisle at
    confidence ≥ 0.6. Several look right once the tags are read (Nutri-Grain,
    tagged `breakfast-cereals`, went to Breakfast cereals). No figure above
    depends on them.
*   **Where the model and the reference disagreed.** Of the 18 disagreements
    with tags, most were boundaries a person could argue either way:
    *   canned fish (Pantry or Meat & seafood);
    *   granola bites and cereal bars (Snacks or Breakfast cereals);
    *   prepared salads (Ready meals or Fruit & vegetables);
    *   packet pasta meals and soups (Pantry or Ready meals).
*   **Confident disagreements.** With tags, the disagreements that remained
    above 0.6 were mostly confident boundary calls. A higher threshold cannot
    remove those. The earlier draft settled them with tag rules; the
    definitions experiment below settles them in the descriptions instead.

### The definitions experiment

A second experiment on 2026-10-31 asked whether the boundaries could be made
consistent in the Aisle descriptions alone, with no rules. It used the same
300 products, tags and Ollama setup as the pilot. Its scripts and data were
not committed.

*   **The reference.** Two AI assistants, working independently, labelled the
    300 products from a written guide (the order of principles in
    [The Aisles](#the-aisles) with an earlier version of its descriptions).
    Neither saw any model output. They agreed on 292 of 300 (97.3%). Their
    eight disagreements, and the products their guide did not cover, became
    the boundary decisions listed under [Open Questions](#open-questions). Five
    of the 292 agreed rows were changed by those decisions (tomato purée,
    crushed garlic and fresh ravioli to Pantry, falafel to Meat & seafood,
    baked beans to Ready meals) and are scored against the decision. As in the
    pilot, the reference is not a person's: it shows whether Clef follows the
    written definitions, not whether shoppers agree with them.
*   **The prompts compared**, each scored on the 292 rows (the readers'
    `none` and `unsure` rows left out):

    | Prompt | Agreement, no threshold | Kept at confidence ≥ 0.6, and their agreement |
    | :-- | :-- | :-- |
    | The pilot's instruction and descriptions | 87.7% | 85% kept; 92.8% agree |
    | The same, with the earlier draft's nine tag rules | 86.3% | 88% kept; 90.2% agree |
    | The order of principles written into the instruction as steps, with positive self-contained descriptions | 93.5% | 92% kept; 97.0% agree |
    | A one-line instruction with the same descriptions | 94.5% | 89% kept; 97.3% agree |
    | Four smaller questions (who it is for, is it a meal, what it is made of, what form it is), combined in code by the order | 91.1% | 90% kept; 95.0% agree |
    | **A one-line instruction with the committed descriptions** | **95.9%** | **88% kept; 99.2% agree** |

    The first two rows were written for different boundaries, so they are not
    a like-for-like comparison with the rest. The last four are.
*   **What made the difference** was the descriptions, not the instruction.
    Clef scores every option in one pass, with no step-by-step reasoning, so
    a procedure in the instruction gained nothing over one line. The old
    descriptions mentioned foods in Aisles they did not belong to ("Canned fish
    goes to Pantry" inside Meat & seafood); the new ones name each food only
    in its own Aisle. The four-question variant scored lower, and was dropped.
*   **Rules.** Of the 19 products the nine tag rules would have decided, Clef
    alone, with the committed descriptions, matched the readers on all 19.
    The rules would have given 7 of them a different Aisle (see
    [Deciding a product's Aisle](#deciding-a-products-aisle)).
*   **Repeatability.** The one-line prompt was run twice. Both runs gave the
    same choice and the same confidence for all 300 products.
*   **Remaining confident errors.** With the committed descriptions, two
    products above 0.6 disagreed with the readers: granola bites (Breakfast
    cereals at 0.73, against Snacks) and a fruit-and-nut "shot" bar (Drinks
    at 0.60).
*   **Time.** The median request took 0.57 s and the 95th percentile 0.61 s,
    against 0.86 s and 1.05 s in the pilot, on the same machine with a
    different load; the cost estimates in
    [Maintainer cost](#maintainer-cost) keep the pilot's slower figure.

## The Problem

A new user opens the picker and sees no Foods until they type. They must
already know a product's name or have the package in hand to scan. Someone
setting up their first day of logging may know the kind of food they buy ("a
yoghurt") without its brand or exact name, and has no way to look around.

Search also misses on partial knowledge. A search for "chips" does not match
British products named "crisps"; the Snacks Aisle lists both.

The bundle cannot support browsing today. Its product lines have no grouping
field, and the builder drops every Open Food Facts category field from the
dump. Open Food Facts' own groupings do not fit:

*   **Category tags** run to thousands of distinct values. About one product
    in six has none, and products of the same kind can carry different tags
    (one yoghurt tagged `en:greek-style-yogurts`, another only `en:yogurts`).
*   **Food groups** (the PNNS groups, from France's national nutrition and
    health programme) sort food by nutrition policy ("sugary snacks",
    "composite foods"). They are not how people shop, and their names describe
    the food in nutrition-policy terms.

## Goals

1.  **A new user can find a product without knowing its name.** The picker
    lists the Aisles before the user types. An Aisle lists its products, the
    most scanned first, and can be searched within.
2.  **Aisles match what users expect.** The list has 14 Aisles, each named in
    everyday words. Every boundary is settled by one stated order of
    principles (see [The Aisles](#the-aisles)), not case by case. A person's
    labels on a held-out sample agree with the pipeline at the bar in
    [Measuring the labels](#measuring-the-labels).
3.  **Labels are measured.** A reference set labelled by a person gives
    overall agreement and coverage, and each Aisle's precision, including the
    precision of the products Browse shows first. CI fails if they fall below
    the bar.
4.  **Builds stay reproducible and offline.** The bundle is built from the
    dump and committed files only. No model, network or GPU is needed to build
    it from committed labels, to run CI, or to run the app. A refresh that
    adds or changes products needs those products labelled first, which needs
    the model and a GPU (see [Maintainer cost](#maintainer-cost)).
5.  **A product with no clear Aisle has none.** A wrong Aisle is worse than
    no Aisle: a product with no Aisle is still found by search. The confidence
    threshold, not the model's `other` answer, is what leaves a product out.
6.  **Agents get the same Aisles.** `searchAgentPlatformFoods` can list and
    search within an Aisle. It reads the same bundle and the same Aisles as
    the picker; as today, its typed-search order (scans) differs from the
    device's (bm25), and it returns at most 50 products where the picker shows
    100.

## Non-Goals

*   **Aisles for User Foods, Recipes or USDA Foods.** User Foods are already the
    first rows in the picker. The USDA seed has three Foods. A larger USDA seed
    would need its own Aisle labels (see [Future Improvements](#future-improvements)).
*   **Aisles for live-only products.** A product fetched from Open Food Facts
    that is not in the bundle has no Aisle until a later bundle contains it.
    It is still found by search.
*   **Sub-aisles or several Aisles per product.** One level, one Aisle.
*   **User-editable Aisles.** Aisles are reference data, like the bundle. A
    user who disagrees with one can still search for the product.
*   **Ranking by anything but scans.** Within an Aisle, the order is the
    bundle's scan count, as in name search on the server. The effect on users
    in each launch country is reported by the builder and accepted for now
    (see [Risks](#risks)).
*   **Running the model anywhere but a maintainer's machine.** Not on the
    device, not on the server, not in CI.
*   **Paging past 50 products for agents.** An agent can search within an
    Aisle for more.

## Open Questions

None is open. Both were decided by the author on 2026-10-31.

1.  **Boundary foods. Resolved (2026-10-31).** An earlier draft settled five
    disputed boundaries one at a time, three of them with tag rules, and the
    answers followed different principles (canned fish by storage, cereal bars
    by form, prepared salads by preparation). They are now all settled by the
    order of principles in [The Aisles](#the-aisles), and each disputed food is
    named in the one Aisle description that owns it:

    | Food | Aisle |
    | :-- | :-- |
    | Canned fish | Meat & seafood (it is fish, as canned vegetables are vegetables) |
    | Cereal, muesli and granola bars; granola bites | Snacks |
    | Salads with dressing, grains, pasta or protein | Ready meals; salad leaves and undressed mixes stay in Fruit & vegetables |
    | Soups, packet and canned meals, instant noodles, whatever their storage | Ready meals |
    | Breakfast biscuits | Sweets & desserts, with the other biscuits |
    | Croissants, pains au chocolat, brioche, Danish pastries | Bread & bakery; cakes stay in Sweets & desserts |
    | Plant-based meat alternatives (vegan burgers and sausages, falafel) | Meat & seafood |
    | Coffee creamers; margarine and plant-based butters | Dairy & eggs |
    | Tomato purée and paste, garlic and ginger pastes, vinegar | Pantry |
    | Maple and golden syrup | Sauces & spreads |
    | Heat-and-eat sides (microwave rice, flavoured grain pouches, baked beans) | Ready meals; pasta of any kind, fresh filled pasta included, stays in Pantry |
    | Dietary supplements (fish oil, vitamins, electrolyte tablets); energy bars and gels | Protein & supplements |
    | Drink powders and concentrates (hot chocolate, cordial) | Drinks |

    The rows from croissants down come from the
    [definitions experiment](#the-definitions-experiment): they are where two
    independent readers of an earlier guide disagreed, or where the guide did
    not cover a product. A later change to any of them is a description change
    (see [CUJ 8](#cuj-8-a-maintainer-settles-a-boundary)).
2.  **Clef's licence. Resolved (2026-10-31).** Clef is released under the
    Apache License 2.0, which places no restriction on the model's outputs.
    The labels file is therefore published under the ODbL with the bundle, as
    the rest of the derived database is. Clef runs only on the maintainer's
    machine and is never redistributed, so its own licence text is not added
    to the bundle. No other decision model has been tried; a substitute would
    need its own pilot, its own confidence threshold derived from that pilot,
    and a comparison with [Alternative E](#alternative-e-a-generative-model-prompted-to-answer-in-json).

## Critical User Journeys (CUJs)

### CUJ 1: A new user browses for a snack

*   **Given** a user with no logged Foods and the bundle installed,
*   **When** they tap **Add Food**,
*   **Then** the picker shows the new-user line from
    [Unified Food Search](unified-food-search.md), and under the
    label "Browse" one row for each of the 14 Aisles, in the order of
    [The Aisles](#the-aisles).
*   **When** they tap **Snacks**,
*   **Then** the list shows the 100 most scanned Snacks on the device, the
    search field's hint becomes "Search Snacks", and the filter chips are
    replaced by a header with a back button and the title "Snacks".
*   **When** they tap a product,
*   **Then** the log-portion screen opens, as from any Open Food Facts row.

### CUJ 2: Search within an Aisle

*   **Given** the Dairy & eggs Aisle is open,
*   **When** the user types "greek",
*   **Then** the list shows the Dairy & eggs products whose name or brand
    matches "greek", by the device's
    [search rules](open-food-facts.md#search-and-barcode-rules). No online
    search row is shown, because live results carry no Aisle.

### CUJ 3: Leave an Aisle

*   **Given** an Aisle is open with a typed query,
*   **When** the user taps the header's back button, uses the system back
    gesture, or taps outside the sheet,
*   **Then** the Aisle closes, the search field is cleared, and the picker
    shows the filter that was selected before the Aisle opened, with its
    blank-query view. The sheet stays open.

### CUJ 4: A product has no Aisle

*   **Given** a bundled product whose label was below the confidence
    threshold, so its Aisle is empty,
*   **When** the user searches for it by name,
*   **Then** it is found as before, and it appears in no Aisle.

### CUJ 5: The first install is still running

*   **Given** a fresh install whose bundle is still being written,
*   **When** the user opens the picker,
*   **Then** no Browse section is shown. When the bundle status becomes
    `ready`, the Browse section appears. If the app is killed during the
    install, the next start runs it again, as today (the install is one
    transaction).

### CUJ 6: An agent lists an Aisle

*   **Given** an agent with an API key,
*   **When** it calls `GET /agent/foods/platform-search?aisle=snacks&limit=20`,
*   **Then** it receives the 20 most scanned Snacks in the server's bundle,
    each with `aisle: "snacks"`, and the Open Food Facts attribution and
    disclaimer. With `aisle` given, `source` defaults to `openFoodFacts`.
*   **When** it calls the same with `source=usda`,
*   **Then** it receives a 422 response with code
    `agent_platform_search_invalid_request`, because USDA foods have no Aisle.

### CUJ 7: A maintainer refreshes the bundle

*   **Given** a new dump and the committed labels file,
*   **When** the maintainer runs the builder with `--aisle-input-only`, then
    the labeller, then the builder,
*   **Then** the labeller labels only the products that are new or whose name,
    brand or last six Open Food Facts tags changed, and the second build
    writes a bundle in which every product has a current label. Had the
    maintainer skipped the labeller, the second build would have written no
    bundle and named the products that need labels. CI checks that every
    bundled product has a label made for the current question and that the
    reference-set measures still meet the bar.

### CUJ 8: A maintainer settles a boundary

*   **Given** reviewers decide that canned fish belongs in Pantry after all,
*   **When** the maintainer moves "canned fish" from the Meat & seafood
    description to the Pantry description, checks the change on the dev set
    with `label_aisles --dev-only` (about 3 minutes), relabels every product
    (about 10 hours, because the question hash changed), relabels the affected
    reference rows by hand, and rebuilds,
*   **Then** the bundle's Aisles change, and CI re-measures the labels against
    the reference set. The definitions remain the only place the boundary is
    written; there is no rule to keep in step with them.

## Technical Plan (Architecture)

### Overview of the parts

Paths are relative to `apps/mobile/` unless they start with `apps/`,
`packages/`, `agent-skills/` or `docs/`, or are repository-root files.

| Where | Part | Change |
| :---- | :--- | :----- |
| Domain (Dart) | `lib/domain/nutrition/food_aisle.dart` (new) | The `FoodAisle` enum and its UI labels |
| Domain (Dart) | `lib/domain/nutrition/open_food_facts.dart` | Bundle format version 2, with `aisle` on each product line |
| Maintainer tool | `tool/open_food_facts_bundle/aisle_pipeline.dart` (new) | The Aisle definitions, the model question and its hash, the two data files' formats, `resolveFoodAisle`, sampling and `measureAisleLabels`: pure functions, tested |
| Maintainer tool | `tool/open_food_facts_bundle/build_bundle.dart` | Reads Open Food Facts tags, writes the labeller's input, refuses stale labels, assigns each product's Aisle |
| Maintainer tool | `tool/open_food_facts_bundle/label_aisles.dart` (new) | Asks the decision model for labels; samples the reference set; prints the labelling guide |
| Committed data | `tool/open_food_facts_bundle/aisle_labels.ndjson`, `aisle_reference.csv` (new) | The model's labels and the person-labelled reference set |
| Shared Dart | `lib/features/nutrition/import/csv_parser.dart` | Gains the public `escapeCsvField`, moved from the CSV export |
| Bundle | `assets/seeds/open_food_facts_bundle.ndjson.gz`, `assets/seeds/open_food_facts_bundle.LICENSE.md`, `THIRD_PARTY_DATA.md` (repository root) | Rebuilt at format version 2; the licence texts name the new files |
| App data | `lib/data/local/food_reference_database.dart`, `lib/data/repositories/open_food_facts_repository.dart` | An `aisle` column and index; writing the Aisle on install; browse and search within an Aisle |
| App feature | `lib/features/nutrition/repositories/add_food_repository.dart`, `controllers/add_food_controller.dart`, `widgets/add_food_picker.dart` | The Browse section and the Aisle view |
| Server | `apps/server/src/open-food-facts-bundle.ts`, `agent-foods.ts`, `app.ts`, `agent-mcp.ts`, `index.ts` | Reads format version 2; the `aisle` parameter and field |
| Agent skill | `agent-skills/perennia/scripts/prn-code.mjs`, `references/api-operations.md`, `SKILL.md` | Passes and documents `aisle` |
| Contract | `packages/contract/openapi.json`, `packages/contract/src/agent-client.ts` | Regenerated |
| Docs | `CONTEXT.md`, `docs/designs/open-food-facts.md`, `docs/development.md`, `docs/designs/SITEMAP.md` | The Aisle term; pointers to this spec; the three-run refresh |
| CI | `.github/workflows/ci.yml`, `tools/ci-local.mjs` | The `js` path filters gain `food_aisle.dart`, which a server test reads |
| Tests | `test/performance/` and the tests in the [Detailed Implementation Plan](#detailed-implementation-plan) | New budgets and cases |

There is no change to `AppDatabase`, sync, backups, the portable archive,
validation or analytics.

```text
 maintainer machine                                         repository / CI / app
 ──────────────────                                         ─────────────────────
 dump ──► build_bundle --aisle-input-only ──► build/open_food_facts_aisle_input.ndjson
                                                    │
                Ollama + Clef ◄── label_aisles ─────┴──► aisle_labels.ndjson ─┐ (committed)
                                                         aisle_reference.csv ─┤
 dump ──► build_bundle ◄──────────────────────────────────────────────────────┘
              │  (refuses to write a bundle if any label is missing or stale)
              └──► open_food_facts_bundle.ndjson.gz (format 2) ──► app install, server loader
                                                    CI: label coverage, question hash, measures
```

### The Aisles

`FoodAisle` (in `lib/domain/nutrition/food_aisle.dart`) has these values, in
this order, which is the order the picker shows. The id is the enum value's
`name`. The same id is written in the bundle, the labels file and the
reference set, and is used on the agent surface.

**The order of principles.** Supermarket sections are defined by different
principles: who a product is for, how it is prepared, what it is made of, and
what form it takes. A food that two principles place differently is a
boundary, and every boundary is settled by this order. The first that applies
wins:

1.  **Who it is for.** Babies and toddlers (Baby food), adults drinking alcohol
    (Alcohol), people buying sports nutrition or dietary supplements (Protein &
    supplements).
2.  **How it is prepared.** Food eaten as it is after at most heating or
    adding water (Ready meals).
3.  **What it is made of.** A basic food of one kind, fresh, frozen, canned or
    dried, rather than a snack, sweet or drink made from it: dairy or eggs
    (Dairy & eggs), meat or fish (Meat & seafood), fruit or vegetables (Fruit
    & vegetables), bread and bakery (Bread & bakery). A plant-based
    alternative sits with the food it replaces.
4.  **What form it takes.** A cereal eaten from a bowl (Breakfast cereals), a
    snack (Snacks), a sweet treat (Sweets & desserts), a drink (Drinks), a
    sauce or spread (Sauces & spreads).
5.  **Otherwise** a cooking staple or ingredient (Pantry).

The order is applied when the descriptions are written, not by the model.
Clef answers in one pass with no step-by-step reasoning, and writing the order
into its instruction gained nothing in the
[definitions experiment](#the-definitions-experiment). Instead, each
description below is a complete, positive definition. It names the boundary
foods that the order gives it, and it never mentions a food that belongs to
another Aisle ("goes to …" sentences are not used).

| Id | UI label | Description (the model's criterion and the labelling guide) |
| :-- | :-- | :-- |
| `dairyEggs` | Dairy & eggs | Milk, yoghurt, cheese, butter, cream, eggs and coffee creamers, and their plant-based alternatives: plant milks, yoghurts and cheeses, margarine and plant-based butters |
| `breadBakery` | Bread & bakery | Bread and bakery: loaves, rolls, buns, wraps, flatbreads, bagels, crumpets, English muffins, croissants, pains au chocolat, brioche and Danish pastries |
| `breakfastCereals` | Breakfast cereals | Cereals eaten from a bowl: breakfast cereal, muesli, granola and granola clusters, oats and porridge |
| `meatSeafood` | Meat & seafood | Meat, poultry, fish and seafood in any form (fresh, frozen, canned, cured, deli or cooked), including sausages and bacon, and plant-based alternatives to them such as vegan burgers, vegan sausages and falafel |
| `fruitVeg` | Fruit & vegetables | Fruit and vegetables in any form (fresh, frozen, canned or dried), salad leaves, undressed salad mixes and fruit cups |
| `pantry` | Pantry | Cooking staples and ingredients: pasta of any kind, including fresh filled pasta, rice, dried noodles, grains, pulses and canned beans, flour, sugar, baking ingredients, oils, vinegar, stock, tomato purée and paste, garlic and ginger pastes, herbs and spices |
| `saucesSpreads` | Sauces & spreads | Sauces, gravy, condiments, dressings, mayonnaise, dips, sweet and savoury spreads, jams, honey, syrups such as maple and golden syrup, and nut butters |
| `snacks` | Snacks | Savoury snacks and snack bars: chips, crisps, crackers, pretzels, popcorn, nuts, seeds, trail mix, rice cakes, granola bites, and cereal, muesli and granola bars |
| `sweetsDesserts` | Sweets & desserts | Sweet treats: chocolate, lollies and candy, sherbet, biscuits and cookies, cakes, sweet muffins, ice cream, puddings and desserts |
| `drinks` | Drinks | Non-alcoholic drinks and what they are made from: water, soft drinks, juice, cordial and concentrates, coffee, tea, drink powders such as hot chocolate, and energy and sports drinks |
| `alcohol` | Alcohol | Drinks containing alcohol: beer, wine, spirits, cider and premixed drinks |
| `readyMeals` | Ready meals | Food eaten as it is after at most heating or adding water: chilled, frozen and canned meals, soups, instant noodles, packet meals, heat-and-eat sides such as microwave rice, flavoured grain pouches and baked beans, pizza, pies, sandwiches, filled wraps, sushi, salads with dressing, grains, pasta or protein, and meal kits |
| `proteinSupplements` | Protein & supplements | Sports nutrition and dietary supplements: protein powders, protein bars and shakes, energy bars and gels, meal replacements, electrolyte tablets, vitamins, fish oil and other supplements |
| `babyFood` | Baby food | Infant formula and food made for babies and toddlers |

*   **Not grouped by storage.** Frozen peas are Fruit & vegetables, canned
    tuna is Meat & seafood, and a frozen lasagne is a Ready meal (see
    [Alternative H](#alternative-h-storage-aisles-frozen-chilled)). Storage is
    not one of the principles, and the bundle does not record it.
*   **The labelling guide.** `label_aisles guide` prints the order of
    principles and this table as plain text. It is what a person follows when
    filling in the reference set, so the person and the model read the same
    definitions.
*   **Words that name the food.** Labels use everyday words shared by the
    launch countries. Where usage differs, both words appear in the model's
    description ("lollies and candy", "chips, crisps"). UI labels avoid
    nutrition-policy wording such as "sugary" or "processed".
*   **Where the descriptions live.** The descriptions and the order of
    principles are in `tool/open_food_facts_bundle/aisle_pipeline.dart`,
    keyed by `FoodAisle`, with the text above. The app does not need them.
*   **Where the list came from.** See
    [Alternative Q](#alternative-q-a-different-source-or-size-for-the-list).

### The question asked of the model

For each product, the labeller sends one request to `POST <ollama base
URL>/v1/systemone`:

```json
{
  "model": "clef:latest",
  "state": {
    "product": "<name, at most 200 runes>",
    "brand": "<brand, at most 200 runes, or empty text>",
    "open_food_facts_categories": ["<up to the last 6 Open Food Facts tags, en: removed>"]
  },
  "questions": {
    "aisle": {
      "type": "choice",
      "instructions": "Which supermarket aisle does `product` belong in? The product name matters most; `brand` and any `open_food_facts_categories` are hints. Choose `other` only when no aisle fits.",
      "criteria": { "<aisle id>": "<description>", "...": "...", "other": null }
    }
  }
}
```

*   **The state.** `aisleModelState` builds it. `product` is the product's
    name and `brand` its brand (empty text when it has none), each cut to its
    first 200 Unicode code points (runes, not UTF-16 code units, so a cut
    never splits a character). `open_food_facts_categories` holds the last six of
    the product's [Open Food Facts tags](#overview), with `en:` removed. These
    are the most specific ones, in hierarchy order. A product with no tags
    gets an empty list.
*   **The question.** `"type": "choice"` asks for exactly one option.
    `criteria` lists every Aisle id, in `FoodAisle` order, with its
    description, and then `other` with `null`, which is how the endpoint takes
    an option with no description.
*   **The response.** The pilot's responses had this shape (one product, the
    probabilities shortened):

    ```json
    {"answers":{"aisle":{"choice":"sweetsDesserts","confidence":0.9136,"probabilities":{"alcohol":0.0019,"babyFood":0.0019,"…":"…","snacks":0.0246,"sweetsDesserts":0.9194}}}}
    ```

    The labeller reads `answers.aisle.choice` (a string) and
    `answers.aisle.confidence` (a number from 0 to 1) and ignores everything
    else. `confidence` is reported by the model separately from the chosen
    option's probability, and the two can differ (0.9136 and 0.9194 above).
    The threshold uses `confidence`.
*   **A usable answer** has a `choice` that is an Aisle id or `other`, and a
    `confidence` that is a number from 0 to 1.

**The question hash.** `aisleQuestionHash()` is the first 16 lowercase
hexadecimal digits of the SHA-256 of the UTF-8 bytes of the compact JSON of
this object, keys in this order:

```json
{"instructions":"<the instructions above>","criteria":{"dairyEggs":"…","…":"…","other":null},"state":["product","brand","open_food_facts_categories"],"textLimit":200,"tagLimit":6}
```

It changes whenever an id, a description, the instructions, the state's keys,
the 200-rune cut or the six-tag rule changes. Labels made under another
question hash are stale. No version number is bumped by hand.

**Failures.** The labeller sends one request at a time, with a 300-second
timeout.

| What happens | What the labeller does |
| :-- | :-- |
| The first request returns HTTP 404 | Stops before labelling anything, with the message "The server does not serve /v1/systemone; it needs a newer Ollama." Exit status 69 |
| Connection refused, timeout, a status other than 200, a body that is not JSON, or no usable answer | Retries twice, 5 seconds apart. After the third failure the product is left unlabelled and the labeller goes on to the next |
| 10 products in a row are left unlabelled | Stops, writes the labels file (below), which deletes the checkpoint, and exits with status 1 |
| Finished, with some products unlabelled | Writes the labels file without them, names how many in the report, and exits with status 1 |
| Finished, every product labelled | Exits with status 0 |

### Deciding a product's Aisle

`resolveFoodAisle` (in `aisle_pipeline.dart`) decides a bundled product's
Aisle. The first of these steps that gives an answer wins:

1.  **Reference.** If the product's code is in the reference set and a person
    gave it an Aisle, that Aisle. If the person marked it `none`, no Aisle. A
    row marked `unsure`, or not yet labelled, gives no answer at this step.
2.  **Label.** If the product has a current label (see
    [The builder](#the-builder)) whose choice is an Aisle id and whose
    confidence is at least `aisleConfidenceThreshold` (0.6), that Aisle.
3.  Otherwise, no Aisle (`null`). This covers a label of `other` and a label
    below the threshold.

There is no tag-rule step. In the
[definitions experiment](#the-definitions-experiment), Clef alone matched the
readers on all 19 products that the earlier draft's nine tag rules would have
decided. The rules would have given 7 of them a different Aisle: four canned
fish, because the canned-fish decision changed, and three where the tag itself
misled (the canned-fish rule sent a tuna-and-crackers kit to Pantry, the
cereal-bar rule sent a Clif energy bar to Snacks, and the prepared-salad rule
sent a bag of salad leaves to Ready meals). A rule is a second statement of a
boundary that can disagree with the definitions; the definitions are the only
one.

The threshold comes from the definitions experiment, with the committed
descriptions. Products at or above 0.6 agreed with the readers in 254 of 256
cases (99.2%); products below it, in 26 of 36 (72%). Lowering the threshold to
0.5 would keep 93% of products instead of 88% at 97.8% agreement; raising it
to 0.7 would keep 79% for 0.4 percentage points more.

The **prediction** for a product is `resolveFoodAisle` without the reference
step. Sampling and measuring use the prediction, so the measures judge the
pipeline, not the person's own answers.

### The committed data

Both files are in `tool/open_food_facts_bundle/`. They are builder inputs and
are not bundled into the app. Both are UTF-8 with LF line endings, and end
with a newline.

**`aisle_labels.ndjson`** is JSON lines: one header line, then one line per
labelled product, sorted by code.

```text
{"format":"perennia-open-food-facts-aisle-labels","formatVersion":1,"questionHash":"<16 hex digits>","model":"clef:latest","modelDigest":"<Ollama digest>"}
{"code":"0818290014313","inputHash":"352594eedc0b9cad","choice":"dairyEggs","confidence":0.943}
```

*   **The header.** `questionHash` is `aisleQuestionHash()` when the labels
    were made. `model` is the model's `name` as `GET <ollama>/api/tags` lists
    it, and `modelDigest` its `digest` there. Every line in the file was made
    by that model under that question.
*   **Each product line.**
    *   `inputHash` is the first 16 lowercase hexadecimal digits of the
        SHA-256 of the UTF-8 bytes of the request's `state`, encoded as
        compact JSON (no spaces, characters outside ASCII written as
        themselves, keys in the order `product`, `brand`,
        `open_food_facts_categories`). For example, the state
        `{"product":"Greek Yogurt Plain Nonfat","brand":"Chobani","open_food_facts_categories":["dairies","fermented-foods","fermented-milk-products","yogurts","greek-style-yogurts"]}`
        has the hash `352594eedc0b9cad`.
    *   `choice` is an Aisle id or `other`.
    *   `confidence` is rounded to 3 decimal places.
*   **Current and stale.** A label is **current** when the header's
    `questionHash` equals `aisleQuestionHash()` and the line's `inputHash`
    equals the product's current one. Otherwise it is **stale**. The labeller
    also requires the header's `modelDigest` to equal the digest of the model
    it is running before it reuses a label.
*   **Products that leave the bundle.** Lines whose code is no longer in the
    aisle input are removed when the labeller writes the file.
*   **Format.** The file is plain text, so a refresh shows as a reviewable
    diff, and git stores refreshes as deltas. About 41,700 lines of about 97
    bytes is about 4 MB.

**`aisle_reference.csv`** is the reference set, an RFC 4180 CSV file with a
header row:

```text
code,name,brand,categories,aisle,sampled_as,set
0818290014313,Greek Yogurt Plain Nonfat,Chobani,en:dairies en:fermented-foods en:yogurts …,dairyEggs,aisle,test
```

*   **The columns.**
    *   `name` and `brand` are for the person labelling; nothing reads them.
        A cell that starts with `=`, `+`, `-`, `@`, a tab or a carriage
        return is written with a leading `'`, so a spreadsheet does not run
        it as a formula.
    *   `categories` is the product's Open Food Facts tags when the row was
        sampled, `en:` kept, separated by single spaces. Like `name` and
        `brand`, it is for the person labelling; nothing reads it.
    *   `aisle` is filled in by a person from the name, brand and tags in the
        row: an Aisle id; `none` when no Aisle fits; `unsure` when the person
        cannot tell what the product is; or empty when not yet labelled.
    *   `sampled_as` is `random`, `aisle` or `noAisle`, and `set` is `dev` or
        `test` (see [The reference set](#the-reference-set)).
*   **Quoting.** A cell containing a comma, a double quote, a CR or an LF is
    quoted, with `"` doubled, as `escapeCsvField` does. The file is parsed
    with the app's existing `parseCsv`.
*   **Strict and lenient reads.** `parseAisleReference(csv, allowUnlabelled:)`
    rejects an unknown column set, an unknown `aisle`, `sampled_as` or `set`
    value, or a repeated code. With `allowUnlabelled: false` (CI) it also
    rejects an empty `aisle`. The builder and `sample` read with
    `allowUnlabelled: true`.
*   **Sorting.** The file is sorted by code.

**Licence.** The labels and the reference set are derived from Open Food Facts
data (product names, brands and tags). They are part of the derived database
and are published under the ODbL with the bundle. The bundle's licence file and
`THIRD_PARTY_DATA.md` list them, and the bundle header's `attributionText`
names them as well.

#### Malformed files

*   **The parsers.** `parseAisleInputLine`, `parseAisleLabels` and
    `parseAisleReference` throw `FormatException`. Its message names the
    1-based line number (counting a header line or header row) and what is
    wrong.
*   **The labels file.** Its first line must be a header whose `format` is
    `perennia-open-food-facts-aisle-labels` and whose `formatVersion` is 1,
    with `questionHash`, `model` and `modelDigest` as strings. Each later line
    must have exactly the keys `code`, `inputHash`, `choice` and
    `confidence`, a `choice` that is an Aisle id or `other`, and a
    `confidence` from 0 to 1. A code that appears twice is rejected. An empty
    text is no file (no header, no labels).
*   **The aisle input.** Each line must have exactly the keys shown in
    [The builder](#the-builder), with those types.
*   **A reference row whose code is not in the aisle input** is kept in the
    file. It is not counted in the measures, and `sample` keeps it.
*   **Exit status.** The builder, `label` and `sample` print the
    `FormatException`'s message and exit with status 65.

### The builder

`build_bundle.dart` changes as follows. Its numbered steps are those in
[Building the bundle](open-food-facts.md#building-the-bundle).

*   **Tags.** In step 2, each kept product also records its Open Food Facts
    tags: the entries of `categories_hierarchy` that start with `en:`, in
    order, prefix kept. A missing or non-list field records an empty list.
*   **New options.** Two take a path relative to `apps/mobile`, with these
    defaults, in either the `--name value` or the `--name=value` form, as
    `--input` does today:
    *   `--aisle-labels`, default `tool/open_food_facts_bundle/aisle_labels.ndjson`;
    *   `--aisle-reference`, default `tool/open_food_facts_bundle/aisle_reference.csv`.

    The third, `--aisle-input-only`, is a flag. It takes no value: a bare
    `--aisle-input-only` sets it, and `--aisle-input-only=<anything>` is a
    usage error (exit 64). `_parseArguments` returns
    `({String input, String datasetVersion, String aisleLabels, String aisleReference, bool aisleInputOnly})`.
*   **Missing and malformed files.** A missing labels file reads as no
    labels, and a missing reference file as no rows. A file that does not
    parse (see [Malformed files](#malformed-files)) stops the builder with
    the parser's message and exit status 65, which the builder already uses
    for a dump it cannot decompress.
*   **A new step after step 4** (the merge). For each merged product, it
    writes one line to `build/open_food_facts_aisle_input.ndjson` (under
    `apps/mobile`, already ignored by git), sorted by code:

    ```text
    {"code":"0818290014313","name":"Greek Yogurt Plain Nonfat","brand":"Chobani","categories":["en:dairies","en:fermented-foods","…"],"scans":412,"inputHash":"352594eedc0b9cad"}
    ```

    `brand` is `null` when the product has none. `scans` is always a
    positive number, because the builder already drops products with no
    scans. `categories` is all its Open Food Facts tags; `inputHash` is the
    hash of its model state.
*   **With `--aisle-input-only`**, it stops after writing the aisle input and
    the report, writes no bundle, and exits with status 0. This is the first
    run of a refresh. Its report has only the dump section of today's report
    (lines read, malformed and failed lines, products per country and the
    exclusions), then the aisle input's path and product count, and the
    number of products whose label is missing or stale. It has no header,
    hash or size lines, because no bundle was built.
*   **Otherwise, the labels must be current.** It reads the labels and finds
    the bundled products with no label line or a stale label. If there are
    any, it writes no bundle, ends its report with "N products need labels:
    run label_aisles.dart label, then build again.", and exits with status 1.
*   **Otherwise, it resolves Aisles.** It calls `resolveFoodAisle` for each
    product and writes the result as the product line's `aisle`, then writes
    the bundle as today.
*   **The report gains:**
    *   products whose label is missing or stale (always printed);
    *   when every label is current, and so only in a run that writes a
        bundle:
        *   products per Aisle, and per deciding step: reference (a reference
            Aisle or a reference `none`), label, or none (no answer from
            either);
        *   the reference rows not yet labelled, and the `unsure` rows;
        *   the [measures](#measuring-the-labels) for the dev set and for the
            test set, with the test set's failures;
        *   for each Aisle, how many of its 100 most scanned products carry
            each launch country in `countries_tags`.

A refresh is therefore three runs, as in CUJ 7: the builder with
`--aisle-input-only` (about 30 minutes, as a build takes today), the labeller
(only new and changed products), and the builder again.

### The labeller

`tool/open_food_facts_bundle/label_aisles.dart`, run from `apps/mobile` with
`dart run`, has three commands. `label` and `sample` read
`build/open_food_facts_aisle_input.ndjson` (exit 66 if it is missing) and use
the default paths above for the two data files. `guide` reads nothing.

```text
dart run tool/open_food_facts_bundle/label_aisles.dart label \
  --ollama <base URL, for example http://localhost:11434> [--model clef] [--dev-only]

dart run tool/open_food_facts_bundle/label_aisles.dart sample --seed <integer>

dart run tool/open_food_facts_bundle/label_aisles.dart guide
```

A bad or missing option exits with status 64 and the usage text.

**`label`**:

*   **Finds the model.** It reads `GET <ollama>/api/tags`. `--model` (default
    `clef`) matches a listed model whose `name` equals it, or, when the option
    has no `:` tag, equals it followed by `:latest`. The matched entry's
    `name` and `digest` are used in the request and the header. If none
    matches, or the server cannot be reached, it stops with exit status 69
    and a message naming the model and the URL.
*   **Decides what to send.** `reusableLabels` takes two sources, the
    committed labels file and then the checkpoint (below). A label from a
    source is reused when that source's header has the current question hash
    and the running model's digest, and the label's input hash is the
    product's current one. A checkpoint label wins over a committed one for
    the same code. Every other product in the aisle input is sent, in code
    order. The first request also loads the model, which took 48 seconds in
    the pilot.
*   **Checkpoints.** Every 500 products it writes
    `build/open_food_facts_aisle_labels.checkpoint.ndjson`, which has the
    labels file's format and holds only labels made in this or an earlier
    stopped run, under a header with the current question hash and model
    digest. A checkpoint whose header does not match the current question and
    model gives no labels and is deleted when the run starts.
*   **Writes the labels file once, at the end.** It writes the reused labels
    and the new ones, and nothing else, under a header for the current
    question and model, to a temporary file next to `aisle_labels.ndjson`,
    then renames it over the old file. A file never holds labels from two
    models or two questions. It then deletes the checkpoint.
*   **Prints progress:** products to label, products done, the time per
    product, and the estimated time left.
*   **Ends with a report:** labels reused and labels made, unlabelled products,
    the counts by `choice` and by confidence band (below 0.6, 0.6 to 0.9,
    0.9 and above), and then the dev-set [measures](#measuring-the-labels).
    The measures use `resolveAisleBundle` over the aisle input, the labels
    file just written and the reference set; an unlabelled product has no
    Aisle.
*   **`--dev-only`** labels only the dev rows of the reference set and writes
    nothing: no labels file and no checkpoint. It prints the dev measures.
    For them, each dev row's newly made label replaces its committed label,
    and every other product keeps its committed label, treated as current
    whatever its question hash. Browse ranks are therefore those of the
    committed labels, which is enough to compare one description change with
    the last committed run.
    At about 180 rows and 0.9 s each, this takes about 3 minutes. It is how a
    maintainer tries a changed description before starting a 10-hour full
    run.

**`sample`** is described under [The reference set](#the-reference-set).

The labeller never runs in CI and is not a dependency of the app. It uses
`dart:io`'s `HttpClient`, and `package:cryptography`, which the builder
already uses, for SHA-256, so it adds no package.

### The reference set

The reference set has two parts. The **dev set** is for tuning: the
descriptions and the threshold are changed only on the evidence of dev
measures. The
**test set** is held out: CI checks the bar on it, and nobody tunes against it.

**What is drawn**, with these counts as constants in `aisle_pipeline.dart`:

| Set | Drawn as (`sampled_as`) | Rows | Purpose |
| :-- | :-- | :-- | :-- |
| test | `random`: any bundled product | 120 | Overall agreement and coverage |
| test | `aisle`: for each Aisle, products predicted as it among its 100 most scanned (its **Browse rows**) | 15 per Aisle, 210 | Browse precision: what a user sees first |
| test | `aisle`: for each Aisle, products predicted as it outside its Browse rows | 15 per Aisle, 210 | Precision across the Aisle |
| dev | `random` | 100 | Tuning overall agreement and coverage |
| dev | `aisle`: for each Aisle, products predicted as it | 5 per Aisle, 70 | Tuning each Aisle |
| dev | `noAisle`: products predicted to have no Aisle | 10 | Tuning the threshold |

That is 540 test rows and 180 dev rows, 720 in all, or about two hours for one
person at about 10 seconds a row.

*   **Why these counts.** 15 rows is the least that lets a 90% precision bar
    allow one disagreement. 120 random test rows give about 105 rows with a
    predicted Aisle, so the 95% agreement bar allows 5 disagreements. The dev
    set is smaller because it only has to show whether a change helps.
*   **What the counts can show.** These are checks against a clear
    regression, not tight estimates: at 105 rows, a measured 95% has a
    95% confidence interval of about ±4 percentage points, and passing 14 of
    15 does not prove precision is at least 90%.
*   **Browse rows.** X's **list** is the bundle's products whose resolved
    Aisle is X, ordered by `scans` descending, then by `code` ascending, as
    the picker orders an Aisle. A product P's **Browse rank** in X is 1 plus
    the number of products in X's list, other than P, that come before P in
    that order. P counts as in X for its own rank whatever its resolved Aisle,
    because sampling and measuring ask where P would sit if X were right. P is
    in X's Browse rows when its rank is at most `aisleBrowseLimit` (100).
    `buildAisleRanking` sorts every Aisle's list once, and `browseRank` finds
    P's place in it by binary search, so ranking all 41,700 products is not
    quadratic. Sampling and measuring use the same two functions.

**`sample --seed <integer>`** tops the set up to the counts above:

1.  It refuses to sample when any product in the aisle input has no label or
    a stale one, because predictions from stale labels would skew the draw.
    It prints "N products need labels: run label_aisles.dart label, then
    sample again." and exits with status 1, writing nothing.
2.  It works out every product's prediction and Browse rank from the aisle
    input, the labels and the reference rows already present.
3.  For each cell of the table (set, drawn-as, Aisle where it has one), it
    counts the rows already in the file that fall in that cell under the
    current predictions, and draws the shortfall:
    *   an `aisle` cell counts rows of any `sampled_as` in that set that are
        predicted as the Aisle and in (or outside) its Browse rows;
    *   the `noAisle` cell counts dev rows of any `sampled_as` that are
        predicted to have no Aisle;
    *   a `random` cell counts only rows whose `sampled_as` is `random`.

    A cell that has fewer eligible products than its count takes all of
    them.
4.  It draws in this order: test `random`, dev `random`, then for each Aisle in
    `FoodAisle` order its test Browse rows, test rows outside Browse, and dev
    rows, then dev `noAisle`. Each draw is from the eligible products sorted by
    code, minus every product already in the file or drawn earlier in the
    run, shuffled with `Random(seed)` (one generator for the whole run), then
    the first N taken. Drawing random rows first keeps them a uniform sample.
5.  It appends the new rows with an empty `aisle`, re-sorts by code, and
    writes the file (creating it with its header row if it is missing). A
    person then fills in `aisle`, following the guide that `label_aisles
    guide` prints. The file does not include the model's label, so it cannot
    influence the person's answer.

After a change moves predictions (a relabel), running
`sample` again tops up any cell that lost rows. Rows are never removed.

### Measuring the labels

`measureAisleLabels` (in `aisle_pipeline.dart`) compares the pipeline with a
person, using only committed data: the bundle's codes, scans and Aisles, the
reference rows and the labels. The builder and the CI test call the same
function with the same inputs.

1.  **Which rows count.** Rows whose code is in the bundle and whose `aisle`
    is filled in and is not `unsure`. Each set is measured on its own.
2.  **What is compared.** Each row's prediction, from its label, is compared
    with the person's `aisle`, where `none` means no Aisle.
3.  **Overall**, over the `random` rows:
    *   **agreement** is the share of rows with a predicted Aisle whose
        predicted Aisle equals the person's;
    *   **coverage** is the share of rows the person gave an Aisle that have
        a predicted Aisle.
4.  **Per Aisle X**, over every counted row predicted as X:
    *   **Browse precision** is the share of those in X's Browse rows that the
        person gave X;
    *   **precision** is the same share for those outside X's Browse rows.
5.  **Recall per Aisle** (the share of `random` rows the person gave X that
    were predicted as X) is reported, not checked: 120 random rows give
    fewer than 15 rows for most Aisles. Overall coverage checks recall in
    aggregate.
6.  **No rows.** A measure with no rows (`rows == 0`) is reported as "not
    measured". It never divides by zero.

The bar, on the test set, checked by a Dart test in CI. The three bars are
constants in `aisle_pipeline.dart`:

| Measure | Bar |
| :------ | :-- |
| Overall agreement | ≥ 95% (`aisleAgreementBar = 0.95`) |
| Overall coverage | ≥ 85% (`aisleCoverageBar = 0.85`) |
| Browse precision, each Aisle | ≥ 90% (`aislePrecisionBar = 0.90`) |
| Precision, each Aisle | ≥ 90% (`aislePrecisionBar`) |
| Rows per Aisle, for each of the two precision measures | ≥ the **required count**: 15, or the number of the Aisle's products in that part (Browse rows, or outside them) when it has fewer |

How a measure is judged:

*   A share is compared with its bar before rounding (`matched / rows <
    bar` fails). Percentages are printed to one decimal place.
*   Overall agreement or coverage with no rows is a failure.
*   For each Aisle part, the row count is checked first. Fewer rows than the
    required count is a failure, and that part's precision is not checked.
    A required count of 0 (the Aisle has no products in that part) is not a
    failure, and the precision is reported as "not measured".

Failures are listed in this order: overall agreement, overall coverage, then
for each Aisle in `FoodAisle` order its Browse row count, Browse precision,
row count outside Browse and precision outside Browse. Each failure is one of
these texts, and the tests check them exactly (`<id>` is the Aisle id, `n` is
the number of rows):

```text
overall agreement 93.3% is below 95.0% (n=105)
overall agreement: not measured
overall coverage 80.0% is below 85.0% (n=110)
overall coverage: not measured
too few rows for drinks in Browse: 12 of 15
browse precision for snacks 86.7% is below 90.0% (n=15)
too few rows for babyFood outside Browse: 3 of 9
precision for snacks outside Browse 85.7% is below 90.0% (n=21)
```

These are the eight forms; one run lists only the failures it finds. In "too
few rows", the second number is the required count.

*   **Where the bar comes from.** In the
    [definitions experiment](#the-definitions-experiment), the committed
    descriptions reached 99.2% agreement among the products kept at 0.6,
    which were 88% of the products counted. The 95% bar leaves room for a
    person's labels to differ from the AI readers', and 88% is a share of all
    counted products, not coverage as defined here, so the coverage bar stays
    at 85%. The 90% precision bars are a product decision: at most one
    product in ten in an Aisle is in the wrong place.
*   **When the bar is missed.** The pull request cannot merge while the CI
    test fails. The maintainer changes descriptions, judging each
    change on the dev measures (`--dev-only`, then the builder's report), and
    relabels. If the test set still fails after the dev set passes, the
    author decides one of these, each recorded in the pull request and, for
    the last two, in this spec:
    *   move the current test rows to dev (change `set`) and draw a fresh test
        set with `sample` and a new seed;
    *   merge an Aisle into another, which changes the question hash;
    *   change a bar.

### The bundle file, format version 2

`bundleFormatVersion` becomes `2`, in the app and on the server.

*   **Header.** Unchanged except `formatVersion`, and `attributionText`, which
    also names `apps/mobile/tool/open_food_facts_bundle/aisle_labels.ndjson`,
    `aisle_reference.csv` and `label_aisles.dart`.
*   **Product line.** It gains a last key, `aisle`, with an Aisle id or
    `null`. The key is required, so the key order stays fixed and the
    encoder's round-trip check (in `open_food_facts_mapping_test.dart` and
    `open_food_facts_bundle_asset_test.dart`) still holds.

    ```json
    {"code":"0818290014313","name":"Greek Yogurt Plain Nonfat","brand":"Chobani","isLiquid":false,"servingLabel":"serving","servingSize":170,"packageSize":907,"nutrients":{"energy":"53","protein":"10","carbohydrate":"3.6","fat":"0"},"modifiedAt":1745020800,"scans":412,"aisle":"dairyEggs"}
    ```

*   **Decoders.** Both decoders reject a line with no `aisle` key, and an
    `aisle` that is neither `null` nor an Aisle id. The Dart decoder throws
    `FormatException`, and the server throws its line error, as for other
    fields.
*   **Size.** The key adds about 20 bytes per line before compression and
    about 0.1 MB to the compressed bundle, which is 2.2 MB today, against the
    6 MB budget.

In Dart:

```dart
typedef BundleProductLine = ({MappedOpenFoodFactsProduct product, FoodAisle? aisle});

String encodeBundleProductLine(MappedOpenFoodFactsProduct product, {FoodAisle? aisle});
BundleProductLine decodeBundleProductLine(String line);
```

`aisle` is a named parameter that defaults to `null`, so existing callers that
encode products with no Aisle compile unchanged.

### On the device

`FoodReferenceDatabase.schemaVersion` becomes `2`.

*   **Schema.** `open_food_facts_products` gains `aisle` (text, nullable) and
    the index `open_food_facts_products_aisle_rank` on `(aisle, scans DESC,
    code)`, created in `_createSearchIndex`.
*   **The index.** The Aisle list is `WHERE aisle = ? ORDER BY scans DESC,
    code LIMIT 100`. Without the index, every Aisle opened scans and sorts all
    41,700 rows; with it, the read walks the first 100 index entries for that
    Aisle. It costs about 1 MB. The performance test measures the read with
    the index.
*   **The update trigger.** `open_food_facts_products_au` becomes `AFTER
    UPDATE OF name, brand`, so writing an Aisle (or an `origin`) does not
    rewrite the row's FTS5 search entry.
*   **Upgrade.** The existing upgrade rule applies: drop everything, create
    the schema, and the missing content hash makes the installer run. The
    device cache is lost once. The app has not been released, so no user
    loses products they opened. This is the first time the upgrade path runs,
    and a test covers it.

**`productCompanion`** gains a named parameter:

```dart
OpenFoodFactsProductsCompanion productCompanion(
  MappedOpenFoodFactsProduct product, {
  required String origin,
  FoodAisle? aisle,
});
```

With `origin` `bundle`, the companion sets `aisle` to `aisle?.name`. With
`origin` `online`, `aisle` must be `null` (an `ArgumentError` otherwise) and
the companion leaves `aisle` absent, so an insert stores `NULL` and an update
does not touch it.

**`replaceBundle`** (the install transaction) runs, in order:

1.  It reads the codes of every `online` row into a set.
2.  It deletes every `bundle` row, as today.
3.  It sets `aisle` to `NULL` on every `online` row
    (`UPDATE open_food_facts_products SET aisle = NULL WHERE origin = 'online'`).
    An `online` row then has an Aisle only if the current bundle gives it one.
4.  For each product line, in the existing batches, it inserts
    `productCompanion(line.product, origin: bundle, aisle: line.aisle)` with
    `_replaceWhenNewer()` on conflict. `_replaceWhenNewer` does not list
    `aisle`, so the newer-copy rule never writes or clears it. A new row gets
    the bundle's Aisle from the insert.
5.  For a product whose code is in the set from step 1, it adds to the same
    batch, after the insert, an update of that row by code that sets `aisle`
    to the line's Aisle. This is the only write of an Aisle onto an existing
    row, and it runs whether or not the row kept its newer values: the Aisle
    is Perennia's label, not Open Food Facts data, so the change-date rule in
    [One product, one row](open-food-facts.md#one-product-one-row) does not
    apply to it.
6.  It records the content hash, as today.

The two writers of `online` rows, `keepProduct` (from the repository's
`keepOpenedProduct`) and the store after a live barcode lookup in
`lookupBarcode`, call `productCompanion` with no `aisle`. A new `online` row
has none, and an existing row keeps the Aisle it has.

New and changed reads in `FoodReferenceDatabase`:

| Method | Query |
| :----- | :---- |
| `productsInAisle(String aisle, int limit)` | `SELECT * FROM open_food_facts_products WHERE aisle = ? ORDER BY scans DESC, code ASC LIMIT ?`. SQLite sorts `NULL` last in descending order, so `online` rows with no scan count come last |
| `searchProducts(String match, int limit, {String? aisle})` | Today's FTS5 query, with `AND p.aisle = ?` when `aisle` is given. The limit applies after the filter |

`productsByCodes` does not change.

`OpenFoodFactsRepository` gains, and changes:

```dart
/// An Aisle's products, most scanned first.
Future<List<PlatformFoodRecord>> productsInAisle(FoodAisle aisle, {required int limit});

/// As today; with [aisle], the name matches are only that Aisle's. Barcode
/// matches are kept whatever their Aisle.
Future<List<PlatformFoodRecord>> searchLocal(String query, {int limit = 50, FoodAisle? aisle});
```

*   **Barcode matches.** A typed barcode inside an Aisle still finds its
    product, even in another Aisle: the user typed an exact code.
*   **When the database is unavailable.** Like `searchLocal`, `productsInAisle`
    returns an empty list when the database cannot be opened.
*   **The stub.** `StubOpenFoodFactsRepository.productsInAisle` returns an
    empty list.

**The coverage guarantee.** Every `FoodAisle` has products in the committed
bundle: the measures need at least 15 test rows per Aisle in its Browse rows,
and the bundle asset test checks every Aisle directly. So the picker lists
every Aisle once the bundle is ready, without asking the database which ones
have products.

### The picker

This part depends on the picker that
[Unified Food Search](unified-food-search.md) builds. It uses, by their names
in that spec:

*   the **All** filter (`AddFoodPickerFilter.all`) and the **Open Food Facts**
    filter, and their blank-query views;
*   the new-user line in the All blank-query view;
*   `YourFoods`, loaded once per opening, which supplies Last Portions to
    Catalogue rows ([Your foods](unified-food-search.md#your-foods));
*   picker items and their key, made from `(foodSource, id)`
    ([Picker items](unified-food-search.md#picker-items));
*   `searchResultLimit` (50), the limit for a typed query;
*   the attribution footer and its key (`attributionFooterKey`);
*   the picker's controller starting fresh each time the sheet opens.

**`AddFoodRepository`** gains:

```dart
/// A blank [query] lists the Aisle's products, most scanned first, up to
/// [limit]; a typed one searches within it, up to [limit].
Future<List<FoodPickerItem>> browseAisle(
  FoodAisle aisle, {
  String query = '',
  required int limit,
  required YourFoods yourFoods,
});
```

*   **Rows.** Items are built by the existing `_openFoodFactsItems`, which
    takes Last Portions from `yourFoods` as phase 1's Catalogue rows do, so
    they carry Last Portions and come from Open Food Facts.
*   **Constants.** `aisleBrowseLimit = 100`, in
    `lib/domain/nutrition/food_aisle.dart`, for a blank query. The picker's
    repository and the maintainer tool both import it, so Browse precision
    measures the rows the picker shows. A typed query within an Aisle uses
    `searchResultLimit`.
*   **More than shown.** The picker treats a blank-query list with exactly
    `aisleBrowseLimit` items as cut, with no extra read. An Aisle with exactly
    100 products would show the "Showing the 100 most scanned" line when
    nothing more exists; that is accepted for one extra line of text.

**`AddFoodPickerState`** gains one field, `aisle` (`FoodAisle?`): the open
Aisle, or `null`. Only `_load` sets it. `copyWith` keeps it, and gains
`clearAisle` (as it has `clearBarcode`) to set it to `null`.

**`AddFoodPickerController`** keeps a private `FoodAisle? _aisle` next to
`_query` and `_filter`. While an Aisle is open, `_filter` keeps the filter
that was selected before, so closing the Aisle needs nothing to restore.

| Action | With no Aisle open | With an Aisle open |
| :-- | :-- | :-- |
| `openAisle(aisle)` | Cancels the debounce, sets `_aisle` and clears `_query`, then refreshes | Not reachable (Browse is not shown) |
| `closeAisle()` | Does nothing | Cancels the debounce, clears `_aisle` and `_query`, sets the state at once to the current state with `clearAisle: true`, an empty query and no results, then refreshes |
| `_load` (every refresh) | As in phase 1 | Calls `browseAisle(_aisle, query: _query, limit:, yourFoods: _yourFoods)`, with `aisleBrowseLimit` for a blank query and `searchResultLimit` for a typed one, and returns a state with `aisle: _aisle` |
| `setQuery` | As today | As today: debounced, then a refresh, which goes through `_load` |
| `submitQuery` | As in phase 1 | Refreshes the device's matches with the current data kept on screen and returns `null`. No live search is made |
| `selectFilter` | As today | Clears `_aisle`, then as today |
| `_reloadDeviceMatches` (the bundle becomes `ready`) | As in phase 1 | Runs `browseAisle` as `_load` does, and applies the result only if `_aisle`, `_filter` and `_query` are unchanged |
| A barcode from the scanner | As today | The picker calls `closeAisle()`, then `lookupBarcode` as today, which may make a live request |

The debounce and the search generation work for `browseAisle` as they do for
`search`. A failed `browseAisle` reads as the picker's existing error state,
as a failed `search` does. Each time the picker opens, it starts with no
Aisle, because its controller starts fresh.

**The widget.** `AddFoodPicker` becomes a `ConsumerStatefulWidget` that owns a
`TextEditingController` for the search field. The field's `onChanged` calls
`setQuery`, as today. Every place that opens or closes an Aisle (an Aisle row,
the back button, the `PopScope`, a scanned barcode) clears the text controller
first, then calls the controller method. The hint is the phase 1 hint with no
Aisle open, and "Search <label>" with one open.

**The Browse section.**

*   **Where it shows.** It follows the existing content in two blank-query
    views:
    *   the **All** filter: after the Your foods rows, or after the new-user
        line and Scan button;
    *   the **Open Food Facts** filter: after its "Search Open Food Facts by
        product name, brand or barcode." line.
*   **When it shows.** Only when `bundleStatus` is `ready`. It is never shown
    for a typed query, or in the Your foods or USDA filters.
*   **Layout.** The label "Browse" (`label` style, `textSecondary`), marked as
    a semantics header, then one list row per `FoodAisle`, in order.
*   **Each row.** The Aisle's UI label in body text, and a trailing
    `Icons.chevron_right` in `textSecondary`. Rows are at least 48 dp tall,
    separated by hairline dividers (`divider-*` tokens). There are no colours
    or icons per Aisle, because category colours belong to exercise
    Categories.
*   **Semantics.** Each row is a button whose semantic label is "<label>,
    aisle".

**The Aisle view**, while `aisle` is set:

*   **The header.** The filter chips are replaced by a header row: an
    `IconButton` with `Icons.arrow_back`, tooltip "Back", calling
    `closeAisle`, then the Aisle's label in `titleMedium`, marked as a
    semantics header.
*   **The search field.** Keeps its place, with the hint "Search <label>".
    The header's Scan barcode button stays.
*   **Blank query.** The Aisle's rows. When there are exactly
    `aisleBrowseLimit` rows, the last item is the line "Showing the 100 most
    scanned. Search to find more." (secondary text).
*   **Typed query.** The matching rows, or "No foods match in <label>."
    (secondary text).
*   **Not shown:** the online slot, the "From Open Food Facts" live group, and
    the bundle line (as phase 1 names them).
*   **Attribution.** The footer shows whenever there is a row, as in the Open
    Food Facts filter.
*   **Back.** The picker wraps its content in a `PopScope` whose `canPop` is
    `aisle == null`. With an Aisle open, its `onPopInvokedWithResult` calls
    `closeAisle` and the sheet stays open. This covers the system back
    gesture and a tap on the barrier outside the sheet, which both pop
    through `Navigator.maybePop`. Dragging the sheet down closes the sheet,
    as it does today.

**Keys**, as static members of `AddFoodPicker`:

| Key | Widget |
| :-- | :-- |
| `Key('nutrition.addFood.browseLabel')` | The "Browse" label |
| `Key('nutrition.addFood.aisle-<id>')`, from `aisleRowKey(FoodAisle)` | An Aisle row |
| `Key('nutrition.addFood.aisleBack')` | The header's back button |
| `Key('nutrition.addFood.aisleTitle')` | The header's title |
| `Key('nutrition.addFood.aisleMoreLine')` | The "Showing the 100 most scanned" line |
| `Key('nutrition.addFood.aisleNoMatch')` | The no-match line |

### Agent surface

`searchAgentPlatformFoods` (`GET /agent/foods/platform-search`, command-map
name `search-platform-foods`, MCP tool `agent_search_platform_foods`) gains
one optional query parameter, one response field and one error response. No
new operation is added: browsing an Aisle is a search with a filter, the same
read the picker makes.

**Request.**

*   **`aisle`** (new): an `AgentPlatformFoodAisle` enum of the 14 ids,
    optional. Description: "Only Open Food Facts foods in this Aisle, a
    consumer-facing group such as `snacks`. Implies `source=openFoodFacts`;
    `source=usda` with `aisle` is rejected with 422, because USDA foods have
    no Aisle. Without `search`, lists the Aisle's foods, most scanned first,
    up to `limit`." The enum's description lists each id with its UI label
    in this form: "Aisle ids: `dairyEggs` (Dairy & eggs), `breadBakery`
    (Bread & bakery), …", in `FoodAisle` order. An unknown `aisle` value is
    rejected by the query schema before the handler runs, as an unknown
    `source` value is today; there is no new response for it.
*   **`source`** loses its schema default. Its description becomes: "Platform
    Food source: usda, the bundled CC0 USDA dataset; or openFoodFacts, the
    Open Food Facts products bundled with the app (ODbL). The default is
    openFoodFacts when `aisle` is given, and usda otherwise. Both are
    offline; the server never calls Open Food Facts."
*   **`search`**'s description becomes: "Case-insensitive name filter; with
    `source=openFoodFacts`, a name or a barcode. Omit it to list the bundled
    USDA catalog (`source=usda`) or an Aisle's Open Food Facts foods (with
    `aisle`); with `source=openFoodFacts` and no `aisle`, omitting it returns
    no foods."
*   **The route's description** (`agent-foods.ts`) changes "(`source=usda`,
    the default, CC0)" to "(`source=usda`, CC0)" and gains, after its first
    sentence: "The default source is openFoodFacts when `aisle` is given, and
    usda otherwise. With `aisle`, results are limited to that Aisle, and
    omitting `search` lists the Aisle, most scanned first."
*   **The MCP tool's description** (`agent-mcp.ts`) changes "source=usda (the
    default) is the CC0 USDA catalog" to "source=usda is the CC0 USDA catalog
    and the default without aisle", and gains the same two sentences after
    "searches the Open Food Facts bundle by name or barcode."

**Behaviour.** The handler resolves `source` as the given value, else
`openFoodFacts` when `aisle` is given, else `usda`. Then:

*   **`aisle` with `source=usda`.** 422 with
    `{"code":"agent_platform_search_invalid_request","message":"USDA foods have no Aisle; omit source or use source=openFoodFacts with aisle."}`
    (schema `AgentPlatformSearchInvalidRequestResponseSchema`). This follows
    the existing handler-level checks, such as
    `agent_effect_window_invalid_request`, which answer 422.
    `searchAgentPlatformFoods` keeps its return type and signals this case by
    throwing the new `AgentPlatformSearchInvalidRequestError`, with the
    message above, as it already signals a missing bundle by throwing
    `OpenFoodFactsBundleUnavailableError`. The REST handler catches it and
    answers 422; the MCP handler catches it and returns an error result with
    the same body.
*   **`aisle`, no `search`.** The Aisle's products in the bundle's name-search
    order (`scans` descending, then `code`), up to `limit`.
*   **`aisle` and `search`.** Today's search, keeping the name matches in the
    Aisle and the barcode matches whatever their Aisle, as the picker does.
    Products are filtered before `limit` applies.
*   **Without `aisle`.** Unchanged.

**Response.** `AgentPlatformFood` gains `aisle` (`AgentPlatformFoodAisle`,
nullable). Its description: "The food's Aisle, a consumer-facing group of
Open Food Facts products; null when it has none, and always null for USDA."

**On the server.** `open-food-facts-bundle.ts`:

*   exports `FOOD_AISLES` (the ids, in `FoodAisle` order),
    `FOOD_AISLE_LABELS` (id to UI label) and
    `type FoodAisle = (typeof FOOD_AISLES)[number]`;
*   accepts only format version 2;
*   requires the `aisle` key on each line and parses it, rejecting an unknown
    id, as the Dart decoder does;
*   gives `searchBundle` an optional fourth argument, `aisle?: FoodAisle`,
    and updates its docstring, which today says listing is not supported.
    Existing three-argument calls keep compiling.

**The contract diff.**

*   `packages/contract/openapi.json` shows the new parameter, the changed
    `source` and `search` (no default, new descriptions), the route's new
    description sentence, the new `AgentPlatformFoodAisle` schema, the new
    response field, and the 422 response with its schema.
    `packages/contract/src/agent-client.ts` shows the new input field, the
    response field and the 422 type.
*   The Dart API client (`apps/mobile/lib/api/perennia_api_client.dart`) does
    not cover the agent operations, and the generated command-map block in
    `agent-skills/perennia/references/api-operations.md` lists only command
    names, methods and paths. Both are regenerated and do not change.
*   Adding an optional parameter and a nullable field is additive. Removing
    `source`'s default does not change any existing request's result.

### Invariants

| Invariant ([AGENTS.md](../../AGENTS.md#non-negotiable-invariants)) | How it holds |
| :--- | :--- |
| Local writes never block on the network. | Browsing and searching within an Aisle are local reads. Nothing on the logging path changes. |
| Sets and Food Entries are self-describing. | A Food Entry's snapshot does not include the Aisle and is not changed by a new bundle. |
| Derived analytics are computed, never stored or synced. | An Aisle is reference data built offline with the bundle, like a product's name. It is not computed from user data. It is stored only in the rebuildable reference database, which does not sync. |
| User-facing delete = archive; restore and import are merge-only. | Not touched. The reference database is outside backups and the portable archive. |
| Sync is silent LWW (last writer wins). | Not touched. |
| Validation is one shared two-tier module. | No rule or tier changes. Aisle ids are checked by the bundle decoders, which reject a malformed bundle as they do today. The agent's 422 is a request-shape check, not a validation rule. |
| No behavioral analytics. | Opening or browsing an Aisle sends nothing and is recorded nowhere. |
| Local-only Mode transmits nothing. | Aisles add no request. The labeller's requests go from a maintainer's machine to the maintainer's own Ollama server, with public Open Food Facts data only, never user data. |

### Vocabulary

[CONTEXT.md](../../CONTEXT.md) changes, in the implementation pull request:

*   **Aisle (new)**: "A consumer-facing group of Platform Foods, named as a
    shopper would find it in a supermarket (Dairy & eggs, Snacks, Drinks),
    from a fixed list. Each bundled Open Food Facts product has at most one
    Aisle, labelled when the bundle is built. Aisles are reference data, not
    user data, and are not editable. Distinct from Category, which groups
    exercises."

### Validation and analytics

*   No validation rule or tier changes.
*   No analytics computation changes.
*   No golden vectors are added. The Aisle ids must agree between Dart and
    TypeScript: a server test reads the Dart enum's source and compares it
    with `FOOD_AISLES` and `FOOD_AISLE_LABELS`, and each side's existing
    bundle test parses the committed bundle with its own decoder.
    `measureAisleLabels` has one implementation, in Dart, covered by Dart unit
    tests.

## Alternatives Considered

### Alternative A: Map Open Food Facts tags to Aisles, with no model

Rules from Open Food Facts tags to Aisles for every product, or rules for
tagged products and the model only for untagged ones (the hybrid phase 1
suggested).

*   **Rejected:** about one product in six has no tags. Covering the tagged
    ones would take hundreds of rules over a contributor-written hierarchy
    that changes, and the hybrid needs those same rules. In the pilot, the
    boundary disputes appeared even when tags were present.
*   **A few rules for boundaries, also rejected.** An earlier draft kept nine
    tag rules: three to settle disputed boundaries and six for the Aisles a
    tag defines (baby food, alcohol, sports nutrition). Each rule restated a
    boundary in a second place, the three boundary rules followed different
    principles from each other, and in the
    [definitions experiment](#the-definitions-experiment) Clef alone matched
    the readers on all 19 products the rules covered, three of which the
    rules would have put in the wrong Aisle because their tag misled. Rules also made some boundary changes cheap (no relabel);
    without them every boundary change is a description change and a full
    relabel, which is accepted for one consistent statement of the
    boundaries.

### Alternative B: The model without Open Food Facts tags

*   **Rejected:** 88.7% agreement against 93.5% with tags in the pilot. The 42
    counted products without tags agreed in 37 cases either way. Sending the
    tags adds about 0.05 s per product, about 35 minutes over a full run.

### Alternative C: Open Food Facts food groups (PNNS)

*   **Rejected:** they are nutrition-policy groups, not shopping groups, and
    their names ("sugary snacks", "composite foods") describe the food in
    policy terms. See [The Problem](#the-problem).

### Alternative D: Classify on the device or the server at run time

*   **Rejected** for three reasons: the model is about 20 GB and needs a GPU;
    the app must work offline; and results could differ between devices and
    model versions. Labelling once, at build time, with committed outputs
    avoids all three.

### Alternative E: A generative model prompted to answer in JSON

*   **Rejected:** a decision model answers a fixed-choice question directly,
    with a probability per option, so there is no free text to parse. Its
    confidence is what the threshold in step 2 uses. The pilot measured this
    model, and a generative model would need its own measurement.

### Alternative F: A hosted model API

*   **Rejected:** the data is public, so privacy is not the concern. A full
    run is about 41,700 short requests, a small cost on a hosted API. The
    concern is pinning: a hosted model can change under the same name. A
    local model's digest is recorded in the labels file, and rerunning it
    costs only the maintainer's time.

### Alternative G: Sub-aisles, or several Aisles per product

*   **Rejected for now:** 14 Aisles of hundreds to thousands of products,
    each searchable, give a new user somewhere to start. A second level would
    double the labelling and reference work before the first level has been
    used.

### Alternative H: Storage aisles (Frozen, Chilled)

*   **Rejected:** a supermarket's frozen section mixes vegetables, meals and
    desserts. Someone looking for peas looks for vegetables. Storage also
    varies by product and country (milk is shelf-stable in some), and the
    bundle does not record it.

### Alternative I: Typing leaves the Aisle

Typing could close the Aisle and run the All search instead.

*   **Rejected:** search within an Aisle is what makes a large Aisle useful
    ("greek" in Dairy & eggs). The header and the search hint make the scope
    visible, and back closes it.

### Alternative J: Aisles as chips or a grid

*   **Rejected:** [DESIGN.md](../../DESIGN.md) reserves pill shapes for filter
    chips, and Aisles navigate rather than filter. List rows follow the
    Exercise List's categories-first pattern. They also stay readable at large
    text scales, where chips would wrap into an uneven block.

### Alternative K: Label live products on the device from their tags

*   **Rejected:** it would need a second, tag-only way of deciding an Aisle on
    the device, which could disagree with the definitions, for the few
    products a user fetches live. Those products are found by search, and a
    later bundle labels the common ones.

### Alternative L: A reference set labelled by an AI model

*   **Rejected as the measure:** the pilot's reference labels were made this
    way, and they were enough to compare approaches. "What users expect" is a
    human judgement, and a person labelling without seeing the model's answer
    does not share the model's errors.

### Alternative M: Write the order of principles into the instruction, or split the question

Two ways to make Clef apply the order of principles itself: write the steps
into the instruction, or ask four smaller questions (who it is for, is it a
meal, what it is made of, what form it is) in the same request and combine the
answers in code by the order.

*   **Rejected:** in the [definitions experiment](#the-definitions-experiment)
    neither beat a one-line instruction with positive, self-contained
    descriptions. The steps scored 93.5% against 94.5%, and the four questions
    91.1%, with slightly slower requests. Clef scores options in one pass and
    does not reason through steps, so the order is applied where the
    descriptions are written.

### Alternative N: One list of the most scanned products, with no Aisles

The blank-query view could list the bundle's most scanned products.

*   **Rejected:** a new user looking for a yoghurt would scroll past the most
    scanned drinks, snacks and spreads first. A flat list helps only for the
    first screenful; grouping is what makes 41,700 products something to look
    around in. Within an Aisle, the order is this list.

### Alternative O: A synonym list for search

A list such as "chips ↔ crisps" could widen name search.

*   **Rejected as a replacement:** it helps a user who already has a word in
    mind, not one who wants to look around, and every regional pair has to be
    found and maintained by hand. It does not conflict with Aisles and could
    be added later.

### Alternative P: Open Food Facts' top-level categories as they are

*   **Rejected:** the top level of `categories_hierarchy` is broad and
    overlapping ("plant-based foods and beverages" covers much of a
    supermarket), one product usually carries several top-level tags, and
    about one product in six has none.

### Alternative Q: A different source or size for the list

The list could follow a published trade classification (such as the GS1
Global Product Classification), or have fewer or more entries (phase 1
suggested 12 to 16).

*   **Rejected:** a trade classification is built for suppliers and
    retailers' systems; its top levels are too coarse ("food, beverage and
    tobacco") and its lower levels too many for a first look. The 14 Aisles
    follow the main sections common to supermarkets in the launch countries.
    Fewer would mix kinds a shopper keeps apart (alcohol with drinks, baby
    food with everything else); more would mean more labelling and
    reference rows per Aisle before the first level has been used. Every Aisle
    had at least one product in the pilot's 300.

### Alternative R: A small classifier trained on the person's labels

It would be deterministic and could run on a CPU, even in CI.

*   **Rejected:** 720 labelled rows over 14 Aisles are too few to train on,
    and they are the measure; training on them would leave nothing to measure
    with.

## Non-Functional Requirements

### Performance

The existing performance test (`test/performance/performance_budgets_test.dart`)
installs a synthetic bundle of `openFoodFactsLocalSearchRowCount` rows into an
in-memory `FoodReferenceDatabase` and times its reads directly. In the
synthetic bundle, row `i` gets no Aisle when `i % 10 == 9`, and
`FoodAisle.values[i % 14]` otherwise, so each Aisle has about 2,600 rows.
Budgets, as constants in `test/performance/performance_budget_thresholds.dart`
and rows in `test/performance/README.md`:

| Read | Constant | Budget |
| :--- | :--- | :----- |
| `productsInAisle('snacks', 100)` | `openFoodFactsAisleBrowseBudget` | under 30 ms |
| `searchProducts(buildFoodSearchMatch('greek yo')!, 50, aisle: 'dairyEggs')` | `openFoodFactsLocalSearchBudget` (existing) | under 100 ms |

### Storage and size

*   **The bundle.** About 0.1 MB more when compressed.
*   **The reference database.** The index adds about 1 MB on the device.
*   **The repository.** `aisle_labels.ndjson` is about 4 MB of text, and a
    refresh changes only new and changed lines.

### Maintainer cost

*   **A full labelling run** is about 41,700 × 0.86 s, about 10 hours, on a
    24 GB consumer GPU. It is needed when the question hash or the model
    changes.
*   **A refresh** labels only new and changed products. Every refresh that
    adds products needs a GPU for that step; a rebuild from committed labels
    (for example after a reference row is relabelled) does not.
*   **A boundary change** is a description change, so it changes the question
    hash and needs a full labelling run.
*   **The first reference set** is 720 rows, about two hours for one person.
*   **A description experiment** with `--dev-only` takes about 3 minutes.

### Accessibility

*   Aisle rows and the back button are at least 48 dp.
*   Each row is a button with a semantic label; "Browse" and the Aisle title
    are semantics headers.
*   The header's back button has a tooltip.
*   Labels wrap rather than truncate at text scale 2.0.
*   Aisles carry no colour, so nothing relies on colour.

### Security and privacy

*   **Requests.** The labeller sends public Open Food Facts product data, and
    nothing else, to the Ollama URL a maintainer gives it.
*   **Access.** Ollama has no authentication. A maintainer runs it on
    `localhost`, or, when it runs on another machine, limits who can reach its
    port at the network layer.
*   **The URL.** It is passed on the command line and never committed.
*   **Product text in the model.** Names and brands are written by Open Food
    Facts contributors and could contain wording meant to steer a label. Each
    is cut to 200 runes. The worst result is a wrong Aisle, which the
    precision measures catch in sample, and which a reference row corrects
    for that product.

### Rollout and rollback

Two implementation pull requests, both targeting `main`:

1.  **Data, bundle and agent surface.** The taxonomy, the tools, the three
    data files, the version 2 bundle, the reference database change, the
    server loader and the agent parameter. The bundle format change breaks
    the server's loader, so these must land together. The pull request
    includes the builder's report and the labeller's report. It is built in
    the ordered steps in the [Detailed Implementation Plan](#pull-request-1-data-bundle-and-agent-surface).
2.  **The picker.** The Browse section and the Aisle view. It starts after
    the phase 1 picker ([Unified Food Search](unified-food-search.md)) has
    merged.

Rollback reverts the pull requests. Reverting the first restores the version 1
bundle, and the reference database's schema version change runs the installer
again.

### Risks

| Risk | Mitigation |
| :--- | :--- |
| The model is withdrawn or changed | Labels are committed, so builds never need it. A new model relabels everything and is recorded in the header |
| Stale labels reach the bundle | The builder refuses to write a bundle with a missing or stale label. CI checks the question hash and that every bundled code has a label. A hand-made bundle that skipped the builder is the gap; the pull request's builder report shows the check passed |
| Refreshes depend on one maintainer's 24 GB GPU | A refresh labels only new and changed products. Without a GPU, the refresh waits and the app keeps its current bundle |
| A boundary decision proves unpopular | One description change, tried on the dev set in about 3 minutes, then a full relabel of about 10 hours, measured in CI (CUJ 8) |
| The descriptions read differently to a person than to Clef | The person labels from the same descriptions (`label_aisles guide`), and the dev and test measures show any gap. In the definitions experiment two independent readers agreed on 97.3% of products |
| The reference set ages as the bundle changes | Only rows in the current bundle count; the per-Aisle row minimum fails CI before any Aisle drops below 15 counted rows, and `sample` tops the set up |
| The reference set reflects one person's judgement | The descriptions are reviewed in the pull request; anyone can relabel a row with the change visible in the diff |
| Ollama changes or removes `/v1/systemone` | The labeller stops with a clear error. Builds are unaffected |
| An Aisle's top products come mostly from one launch country | Ranking is by global scans and product lines carry no country. The builder reports the country split of each Aisle's 100 most scanned products; if one country dominates, per-country ranking is a future change |
| Product names in other languages (French names in Canadian products) | Not measured in the pilot. The test set's random rows include them in proportion, so a problem shows in overall agreement |

## Additional Resources

*   [Open Food Facts Integration](open-food-facts.md): the bundle, the builder,
    the reference database and the agent surface this spec amends.
*   [Unified Food Search](unified-food-search.md): the picker this spec adds to.
*   [Open Food Facts API documentation](https://openfoodfacts.github.io/openfoodfacts-server/api/),
    including the product fields `categories_hierarchy` and `countries_tags`.
*   [Ollama](https://ollama.com), which serves Clef; Clef's model page and
    licence are in Ollama's model library under the name `clef`.

## Future Improvements

*   **Aisles for USDA Foods**, once the USDA seed is large enough to browse,
    labelled by the same pipeline from their descriptions.
*   **Sub-aisles** within the largest Aisles, if user feedback says they are
    too long.
*   **Per-country ranking within an Aisle**, if the builder's country split
    shows one launch country filling an Aisle's top products.
*   **Aisles on the Open Food Facts filter's search results**, as a refinement
    chip row, if user feedback asks to narrow a search by Aisle outside the
    Aisle view.

## Detailed Implementation Plan

### Target Files to Create/Modify

Each entry gives its changes, and its scope where that is not plain from the
path. Paths are relative to `apps/mobile/` unless they start with `apps/`,
`packages/`, `agent-skills/`, `tools/`, `.github/` or `docs/`, or are
repository-root files.

#### Pull request 1: data, bundle and agent surface

Built in this order. Steps 1 to 3 end with `pnpm ci:local mobile` green.
Steps 4 and 5 end with `pnpm ci:local mobile golden contract js sync
workflow_lint` green: those are the jobs that `apps/server/**` and
`.github/workflows/ci.yml` trigger. The `js` and `sync` jobs need Docker.

1.  The Aisle enum, the CSV helper move and the pipeline library: items 1, 3
    and 4, with `test/tool/aisle_pipeline_test.dart` from item 17, which
    tests item 4.
2.  The labeller, and the builder's Aisle input: item 6, and these parts of
    item 5: recording tags, the three new options, writing the aisle input,
    `--aisle-input-only` and its report, refusing missing or stale labels,
    and every new report line. The builder still writes format version 1
    lines.
3.  Run the pipeline and commit its data, item 7, in this order:
    1.  The builder with `--aisle-input-only`, a full `label` run, and
        `sample --seed 1`.
    2.  A person labels every row, following `label_aisles guide`.
    3.  Tuning, on the dev set only. Each description change is tried with
        `label --dev-only`, judged on the dev measures it prints, and kept
        or undone. Nobody looks at the test measures while tuning.
    4.  When the dev measures pass the bar: a full `label` run (the question
        hash has changed if any description did), `sample` again to top up
        any cell that lost rows, and a person labels the new rows.
    5.  The builder, which now writes a bundle (still format version 1, and
        not committed until step 4) and prints the test measures. This is
        the one look at the test set. If it fails, the author
        follows [When the bar is missed](#measuring-the-labels).
    6.  Every description changed in tuning is changed in
        [The Aisles](#the-aisles) in the same pull request.
4.  Format version 2 everywhere, in one commit: item 2, the rest of item 5
    (writing each product's resolved Aisle into its line, and the
    attribution text), items 8 to 12, the CI path filters in item 16, and
    the Dart tests in item 17 not already added, with
    `apps/server/test/open-food-facts-bundle.test.mjs` from item 17. The
    format change, the regenerated bundle and both decoders must land
    together, or the asset tests fail.
5.  The agent parameter, the contract and the docs: items 13 to 16 (less the
    CI path filters), with the other server tests in item 17.

##### 1. `lib/domain/nutrition/food_aisle.dart` (Create)

*   **Scope:** domain; imports nothing outside `dart:`.
*   **Changes:**
    *   `enum FoodAisle` with the 14 values in the order of
        [The Aisles](#the-aisles), in exactly this form, one value per line,
        because a server test reads it:

        ```dart
        enum FoodAisle {
          dairyEggs('Dairy & eggs'),
          // … one line per Aisle, in order …
          babyFood('Baby food');

          const FoodAisle(this.label);

          final String label;
        }
        ```

    *   `FoodAisle? foodAisleById(String id)`, which returns `null` for an
        unknown id.
    *   `const aisleBrowseLimit = 100;`, the one definition of the constant
        (see [The picker](#the-picker)).

##### 2. `lib/domain/nutrition/open_food_facts.dart` (Modify)

*   **Scope:** domain.
*   **Changes:**
    *   `bundleFormatVersion = 2`.
    *   The `BundleProductLine` typedef.
    *   `encodeBundleProductLine(product, {FoodAisle? aisle})` writes `aisle`
        as the last key, `null` when absent.
    *   `decodeBundleProductLine` returns a `BundleProductLine` and throws
        `FormatException` for a missing `aisle` key or an unknown id.

##### 3. `lib/features/nutrition/import/csv_parser.dart`, `lib/data/repositories/csv_export_repository.dart` and `lib/data/repositories/training_repositories.dart` (Modify)

*   **Scope:** shared CSV helpers; no behaviour change.
*   **Changes:** `_escapeCsvField` moves from `csv_export_repository.dart` to
    `csv_parser.dart` as the public `escapeCsvField(String? value)`, with the
    same body. `training_repositories.dart` (the library that
    `csv_export_repository.dart` is part of) imports `csv_parser.dart`, and
    the export calls `escapeCsvField`.

##### 4. `tool/open_food_facts_bundle/aisle_pipeline.dart` (Create)

*   **Scope:** maintainer tool library; pure (no `dart:io`). Imports
    `package:perennia/domain/nutrition/food_aisle.dart`,
    `package:perennia/features/nutrition/import/csv_parser.dart` and
    `package:cryptography/dart.dart` (which exports `DartSha256`;
    `cryptography.dart` does not). Tested from `test/tool/`.
*   **Changes**, declared as below:

    ```dart
    const aisleConfidenceThreshold = 0.6;
    // aisleBrowseLimit is imported from food_aisle.dart, not redefined.
    const aisleModelTextLimit = 200; // Unicode code points (runes), so a cut never splits a character
    const aisleModelTagLimit = 6;
    const aisleModelInstructions = '<the instructions in The question asked of the model>';
    const aisleModelDescriptions = <FoodAisle, String>{ /* the table in The Aisles */ };
    const aislePrinciples = <String>[ /* the five steps of the order of principles in The Aisles, one string each */ ];

    const referenceTestRandomRows = 120;
    const referenceTestRowsPerAislePart = 15; // Browse rows, and rows outside Browse
    const referenceDevRandomRows = 100;
    const referenceDevRowsPerAisle = 5;
    const referenceDevNoAisleRows = 10;
    const aisleMeasureMinimumRows = 15;
    const aisleAgreementBar = 0.95;
    const aisleCoverageBar = 0.85;
    const aislePrecisionBar = 0.90;

    Map<String, Object?> aisleModelState({required String name, String? brand, required List<String> categories}); // name and brand cut to their first 200 runes
    Map<String, Object?> aisleModelRequest({required String model, required Map<String, Object?> state});
    String aisleInputHash(Map<String, Object?> state);
    String aisleQuestionHashOf({required String instructions, required Map<FoodAisle, String> descriptions});
    String aisleQuestionHash(); // aisleQuestionHashOf with the two constants
    String aisleGuideText(); // the order of principles, then each Aisle's id, UI label and description, then the `none` and `unsure` answers

    final class AisleInputLine { final String code; final String name; final String? brand; final List<String> categories; final int scans; final String inputHash; }
    AisleInputLine parseAisleInputLine(String line);
    String encodeAisleInputLine(AisleInputLine line);

    final class AisleLabelsHeader { final String questionHash; final String model; final String modelDigest; }
    typedef AisleLabel = ({String inputHash, FoodAisle? aisle, double confidence}); // `aisle` holds the file's `choice`; null = the model chose `other`
    final class AisleLabels { final AisleLabelsHeader? header; final Map<String, AisleLabel> byCode; } // header null = no file
    AisleLabels parseAisleLabels(String text);
    String encodeAisleLabels(AisleLabels labels); // header line, then lines sorted by code, compact JSON, confidence rounded to 3 places

    enum ReferenceAnswer { aisle, none, unsure, unlabelled }
    enum ReferenceDraw { random, aisle, noAisle }
    enum ReferenceSet { dev, test }
    final class AisleReferenceRow {
      final String code; final String name; final String brand; final List<String> categories;
      final ReferenceAnswer answer; final FoodAisle? aisle; // set only when answer == aisle
      final ReferenceDraw sampledAs; final ReferenceSet set;
    }
    List<AisleReferenceRow> parseAisleReference(String csv, {required bool allowUnlabelled});
    String encodeAisleReference(List<AisleReferenceRow> rows); // header row, sorted by code, escapeCsvField, formula cells prefixed with '
    // parseAisleReference removes a leading ' when the character after it is one the encoder prefixes (=, +, -, @, tab, CR)

    bool isCurrentLabel(AisleLabel? label, AisleLabelsHeader? header, String inputHash);
    FoodAisle? resolveFoodAisle({
      required AisleLabel? currentLabel, // null when missing or stale
      AisleReferenceRow? reference,       // null skips the reference step
    });

    typedef AisleBundleProduct = ({String code, int scans, FoodAisle? aisle}); // aisle = the resolved Aisle
    List<AisleBundleProduct> resolveAisleBundle({
      required List<AisleInputLine> input,
      required Map<String, AisleLabel> labels, // the labels the caller treats as current, by code
      required List<AisleReferenceRow> reference,
    }); // resolveFoodAisle for each input line; a code with no label has no label step

    final class AisleRanking { /* for each FoodAisle, its list sorted by scans descending, then code ascending */ }
    AisleRanking buildAisleRanking(List<AisleBundleProduct> bundle);
    int browseRank(AisleRanking ranking, FoodAisle aisle, {required String code, required int scans}); // as in The reference set: 1-based, the product counted as in `aisle`

    Map<String, AisleLabel> reusableLabels(List<AisleInputLine> input, List<AisleLabels> sources, {required String questionHash, required String modelDigest}); // later sources win
    List<AisleInputLine> labelsToMake(List<AisleInputLine> input, Map<String, AisleLabel> reusable); // input lines with no reusable label
    AisleLabels mergeLabels({required List<AisleInputLine> input, required Map<String, AisleLabel> reused, required Map<String, AisleLabel> made, required AisleLabelsHeader header}); // drops codes not in input; a made label wins
    List<AisleReferenceRow> sampleReference({
      required List<AisleInputLine> input,
      required Map<String, AisleLabel> labels, // current labels only; `sample` refuses to run otherwise
      required List<AisleReferenceRow> existing,
      required int seed,
    }); // returns only the new rows

    typedef AisleShare = ({int matched, int rows}); // rows == 0 means not measured
    final class AisleSetMeasures {
      final AisleShare agreement; final AisleShare coverage;
      final Map<FoodAisle, AisleShare> browsePrecision; final Map<FoodAisle, AisleShare> precision;
      final Map<FoodAisle, AisleShare> recall; // reported only
      final int unsureRows; final int unlabelledRows;
    }
    final class AisleMeasures { final AisleSetMeasures dev; final AisleSetMeasures test; final List<String> failures; }
    AisleMeasures measureAisleLabels({
      required List<AisleBundleProduct> bundle,
      required List<AisleReferenceRow> reference,
      required AisleLabels labels,
    });
    ```

    *   `aisleInputHash` and `aisleQuestionHashOf` use `DartSha256().hashSync`
        over `utf8.encode(jsonEncode(...))`, and write the first 16 lowercase
        hexadecimal digits (8 bytes).
    *   `measureAisleLabels` treats every label as current: CI has no dump, so
        it cannot recompute input hashes, and the builder has already refused
        stale labels. `failures` lists only test-set failures, in the order
        and text forms in [Measuring the labels](#measuring-the-labels).

##### 5. `tool/open_food_facts_bundle/build_bundle.dart` (Modify)

*   **Scope:** maintainer tool.
*   **Changes**, as in [The builder](#the-builder):
    *   Step 2 records each kept product's Open Food Facts tags.
    *   `_parseArguments` accepts `--aisle-labels`, `--aisle-reference` and
        `--aisle-input-only` as stated there, returns the five-field record,
        and the usage text lists the three options.
    *   A new step writes `build/open_food_facts_aisle_input.ndjson`.
    *   With `--aisle-input-only`, it stops after writing the aisle input and
        its shorter report, writes no bundle, and exits with status 0. The
        shorter report is printed by a new `_Report` method, because
        `_Report.print` needs a bundle header and sizes.
    *   Otherwise it refuses missing or stale labels (exit 1, no bundle).
        Then it resolves each product's Aisle with `resolveAisleBundle` and,
        from step 4 of the build order, passes it to
        `encodeBundleProductLine`.
    *   A data file that does not parse exits with status 65.
    *   The report gains the lines listed in [The builder](#the-builder).
    *   `_attributionText` gains the three file names:
        `apps/mobile/tool/open_food_facts_bundle/aisle_labels.ndjson`,
        `aisle_reference.csv` and `label_aisles.dart`.

##### 6. `tool/open_food_facts_bundle/label_aisles.dart` (Create)

*   **Scope:** maintainer tool, command line only; the logic is in item 4.
*   **Changes:**
    *   The `label` command, as in [The labeller](#the-labeller), with the
        failure table in
        [The question asked of the model](#the-question-asked-of-the-model).
    *   The `sample` command, as in [The reference set](#the-reference-set).
    *   The `guide` command, which prints `aisleGuideText()` and exits with
        status 0.
    *   Exit statuses: 0 done, 1 incomplete or refused, 64 usage, 65 a data
        file that does not parse, 66 a missing aisle input, 69 the model or
        the endpoint unavailable.

##### 7. `tool/open_food_facts_bundle/aisle_labels.ndjson` and `aisle_reference.csv` (Create)

*   **Scope:** committed data, made by the pipeline in step 3.
*   **Changes:** the labels file from a full `label` run over the aisle input
    built from a dump downloaded for this pull request (Open Food Facts keeps
    no older dumps, so pull request 1 is also a data refresh, checked as
    `docs/development.md` describes); the reference set from
    `sample --seed 1`, every row labelled by a person.

##### 8. `assets/seeds/open_food_facts_bundle.ndjson.gz` (Regenerate)

*   Built at format version 2 by `dart run tool/open_food_facts_bundle/build_bundle.dart`
    from the same dump as item 7, with the committed labels.

##### 9. `assets/seeds/open_food_facts_bundle.LICENSE.md` and `THIRD_PARTY_DATA.md` (repository root) (Modify)

*   Both name the two data files as part of the ODbL derived database, and
    the labeller as the method that made the labels file.

##### 10. `lib/data/local/food_reference_database.dart` and `lib/data/local/food_reference_database.g.dart` (Modify; the second generated by `dart run build_runner build`)

*   **Scope:** app data.
*   **Changes**, as in [On the device](#on-the-device):
    *   The `schemaVersion` getter returns 2. The `aisle` column on
        `OpenFoodFactsProducts`; `open_food_facts_products_aisle_rank` and
        the `AFTER UPDATE OF name, brand` trigger in `_createSearchIndex`.
    *   `productCompanion` gains `FoodAisle? aisle`.
    *   `replaceBundle` runs the six steps listed in
        [On the device](#on-the-device), using
        `decodeBundleProductLine(...).product` and `.aisle`.
    *   `productsInAisle`, and `searchProducts`' `aisle` parameter.

##### 11. `lib/data/repositories/open_food_facts_repository.dart` (Modify)

*   **Scope:** app data.
*   **Changes:** `productsInAisle` and the `aisle` parameter of `searchLocal`
    on the interface, `DriftOpenFoodFactsRepository` and
    `StubOpenFoodFactsRepository`. In `searchLocal`, the `aisle` goes to
    `searchProducts` only; `productsByCodes` is unfiltered.

##### 12. `apps/server/src/open-food-facts-bundle.ts` (Modify)

*   **Scope:** server.
*   **Changes:** format version 2; `FOOD_AISLES`, `FOOD_AISLE_LABELS` and the
    `FoodAisle` type; `BundleProduct.aisle`; `parseProductLine` requires the
    `aisle` key and rejects unknown ids; `searchBundle(bundle, query, limit,
    aisle?)`, with `aisle` optional, and its docstring, as in
    [Agent surface](#agent-surface).

##### 13. `apps/server/src/agent-foods.ts` (Modify)

*   **Scope:** server.
*   **Changes:**
    *   `AgentPlatformFoodAisleSchema`; the `aisle` query parameter; `source`
        without its default; the new `search`, `source`, `aisle` and route
        descriptions; the response field; the 422 response and
        `AgentPlatformSearchInvalidRequestResponseSchema`.
    *   `searchAgentPlatformFoods({search, source, limit, aisle})` keeps its
        return type, `AgentFoodPlatformSearchResponse`. It resolves `source`
        as in [Agent surface](#agent-surface) § Behaviour, and for `aisle`
        with `usda` throws `AgentPlatformSearchInvalidRequestError`.
    *   `export class AgentPlatformSearchInvalidRequestError extends Error`,
        whose message is the one in [Agent surface](#agent-surface).
    *   `openFoodFactsPlatformFood` sets `aisle`; `usdaPlatformFood` sets
        `null`.

##### 14. `apps/server/src/app.ts`, `apps/server/src/agent-mcp.ts` and `apps/server/src/index.ts` (Modify)

*   **Scope:** server.
*   **Changes:**
    *   Both handlers pass `aisle: query.aisle`. Each catches
        `AgentPlatformSearchInvalidRequestError` next to its existing
        `OpenFoodFactsBundleUnavailableError` catch, and answers with
        `AgentPlatformSearchInvalidRequestResponseSchema.parse({code:
        "agent_platform_search_invalid_request", message: error.message})`:
        status 422 in REST, an error result in MCP.
    *   The MCP tool's description changes as in
        [Agent surface](#agent-surface).
    *   `index.ts` exports `AgentPlatformFoodAisleSchema`,
        `AgentPlatformSearchInvalidRequestResponseSchema` and
        `AgentPlatformSearchInvalidRequestError` with the other
        `agent-foods.js` exports.

##### 15. `packages/contract/openapi.json`, `packages/contract/src/agent-client.ts` (Regenerate)

*   Regenerated by `corepack pnpm --filter @perennia/contract generate`.

##### 16. Agent skill, docs and CI path filters (Modify)

*   `agent-skills/perennia/scripts/prn-code.mjs`: `searchAgentPlatformFoods`
    picks `["search", "source", "limit", "aisle"]`.
*   `agent-skills/perennia/references/api-operations.md`, outside the
    generated command-map block, and `agent-skills/perennia/SKILL.md`:
    describe `aisle`, list the ids with their labels, and add the example
    `node scripts/prn-agent.mjs search-platform-foods --query aisle=snacks`.
*   `CONTEXT.md`: add **Aisle** as worded under [Vocabulary](#vocabulary).
*   `docs/designs/open-food-facts.md`: each section below gains one sentence
    pointing to this spec:
    *   "The bundle file": format version 2 and the `aisle` key.
    *   "Building the bundle": tag capture, the aisle input, the label check
        and Aisle resolution.
    *   "Installing the bundle on the device": schema version 2 and the six
        `replaceBundle` steps.
    *   "One product, one row": the Aisle write is exempt from the
        change-date rule.
    *   "Agent surface": the `aisle` parameter and field.

    Its date line records the amendment.
*   `docs/development.md`, the Open Food Facts refresh steps: a refresh
    becomes the three runs of CUJ 7 (the builder with
    `--aisle-input-only`, `label_aisles.dart label`, then the builder
    again), with `sample` and `guide` for topping up the reference set, and
    the new report lines to check: no missing or stale labels, the per-Aisle
    counts, and the test measures with no failures.
*   CI path filters, landing in step 4 of the build order: the `js` filter
    in `.github/workflows/ci.yml` and `JS_PATHS` in `tools/ci-local.mjs`
    each gain `apps/mobile/lib/domain/nutrition/food_aisle.dart`, and their
    comments name it with the other Dart files the server tests read. Both
    files change in the same commit.

##### 17. Tests for pull request 1 (Create; Modify)

*   `test/tool/aisle_pipeline_test.dart` (Create), importing
    `../../tool/open_food_facts_bundle/aisle_pipeline.dart`:
    *   **`aisleModelState`:** the last six tags, the `en:` filter and its
        removal, an empty list, a missing brand as empty text, and the
        200-rune cut, including a name whose 200th rune is outside the Basic
        Multilingual Plane (one rune, two UTF-16 code units), which is kept
        whole.
    *   **`aisleInputHash`:** the Greek yoghurt state in
        [The committed data](#the-committed-data) hashes to
        `352594eedc0b9cad`, and the state
        `{"product":"Crème fraîche","brand":"","open_food_facts_categories":[]}`
        to `4a9c0a1a6c166aae`.
    *   **`aisleQuestionHashOf`:** a different hash when one description
        changes, and when the instructions change. **`aisleQuestionHash`:**
        equals `aisleQuestionHashOf` of the two constants, and is the same on
        every call.
    *   **Aisle input:** `encodeAisleInputLine(parseAisleInputLine(line))`
        returns `line`; a missing key, an extra key or a wrong type throws
        `FormatException` naming the line.
    *   **Labels:** `encodeAisleLabels(parseAisleLabels(text))` returns `text`
        for a sorted, compact file; confidence rounding; an empty text gives
        no header and no labels. Each rejection in
        [Malformed files](#malformed-files) throws `FormatException`: a
        missing or wrong header, a wrong `format` or `formatVersion`, a
        missing or extra key, an unknown `choice`, a confidence outside 0 to
        1, a repeated code.
    *   **Reference CSV:** quoting of commas, quotes and line breaks; the `'`
        prefix added to formula cells and removed again on parse; `unsure`
        and `none`; an empty `aisle` rejected strictly and read as
        `unlabelled` leniently; unknown values and repeated codes rejected.
    *   **`isCurrentLabel`:** a matching hash and question; a changed input
        hash; a changed question hash; no header.
    *   **`resolveFoodAisle`:** a reference Aisle beats a confident label; a
        reference `none` gives `null` even with a confident label; `unsure`
        and unlabelled rows fall through to the label; the threshold boundary
        (0.6 kept, 0.599 not); `other` gives `null`; no current label gives
        `null`.
    *   **`resolveAisleBundle`:** one product per input line, in input order;
        a code with no label gets only the reference step.
    *   **`reusableLabels`, `labelsToMake` and `mergeLabels`:** a label is
        reused only when its source's question hash and model digest match
        and its input hash is current; a checkpoint label wins over a
        committed one; a source with another model digest gives nothing;
        `labelsToMake` returns the lines with no reusable label; a made label
        wins in the merge; codes that left the input are dropped.
    *   **`sampleReference`:** the same seed gives the same rows; random rows
        are drawn first and are uniform over the input; top-up draws only
        each cell's shortfall, counted as in
        [The reference set](#the-reference-set) (including a `random` dev row
        with no prediction counting toward the `noAisle` cell); existing
        codes are skipped; a cell with fewer eligible products than its count
        takes all of them.
    *   **`buildAisleRanking` and `browseRank`:** rank 1 for the most scanned;
        `scans` descending, then `code` ascending on a tie; a product whose
        resolved Aisle is another Aisle is ranked as if it were in this one,
        without moving the others' ranks.
    *   **`measureAisleLabels`:** a small hand-built fixture with known
        agreement, coverage, both precisions and recall; rows outside the
        bundle and `unsure` rows not counted; a measure with `rows == 0`
        reported as not measured; each of the eight failure texts exactly;
        the failure order; a share just under a bar (189 of 199, 94.97%)
        failing although it prints as 95.0%; a part with too few rows giving
        only the "too few rows" failure.
    *   **Descriptions:** every `FoodAisle` has one; none contains the words
        "goes to" (a description names only its own foods).
    *   **`aisleGuideText`:** contains every principle and every description,
        in order, so the guide is built from the same constants as the
        model's criteria.
*   `test/tool/aisle_data_test.dart` (Create, runs in the `mobile` CI job):
    *   parses the two committed files, the reference set strictly;
    *   checks that every code in the committed bundle has a label line;
    *   checks that the labels header's `questionHash` equals
        `aisleQuestionHash()`;
    *   runs `measureAisleLabels` on the committed bundle and expects no
        failures.
*   `test/domain/open_food_facts_mapping_test.dart` (Modify): the encoder with
    and without an Aisle; the round trip of both; rejection of a missing
    `aisle` key and of an unknown id. Existing tests that use the decoded
    value as a product read `.product` instead, re-encode with
    `encodeBundleProductLine(decoded.product, aisle: decoded.aisle)`, and
    expect the exact lines to end with `,"aisle":null}`.
*   `test/data/open_food_facts_fixtures.dart` (Modify):
    `bundleLines(products, {Map<String, FoodAisle> aisles = const {}})` and
    `bundleBytes(..., {Map<String, FoodAisle> aisles = const {}})`, an absent
    code meaning no Aisle, so existing callers compile unchanged.
*   `test/data/open_food_facts_bundle_asset_test.dart` (Modify): the
    committed bundle decodes at format version 2, and every `FoodAisle` has
    at least one product. The canonical-format check re-encodes with
    `encodeBundleProductLine(decoded.product, aisle: decoded.aisle)`.
*   `test/data/food_reference_database_test.dart` (Modify), against a real
    in-memory SQLite database:
    *   **Installing Aisles:** the install writes them; an `online` row that
        keeps its newer values still takes the bundle's Aisle.
    *   **Clearing them:** an `online` row not in the new bundle loses its
        Aisle.
    *   **Keeping a product:** `keepProduct` on a row with an Aisle, with a
        newer and with an older copy, leaves the Aisle; on a new code, stores
        none.
    *   **`productCompanion`:** an Aisle with `origin` `online` throws.
    *   **Reads:** `productsInAisle` order with `NULL` scans last;
        `searchProducts` with an Aisle.
    *   **The trigger:** the `open_food_facts_products_au` trigger's SQL in
        `sqlite_master` contains `AFTER UPDATE OF name, brand`, so writing
        only an Aisle does not rewrite the FTS5 row.
    *   **A killed install:** `replaceBundle` with a `beforeCommitForTesting`
        that throws, as the existing rollback test does, leaves the previous
        bundle's Aisles.
*   `test/data/food_reference_schema_upgrade_test.dart` (Create): writes a
    file database with the version 1 schema (its `CREATE` statements copied
    into the test as a fixture) and `PRAGMA user_version = 1`, opens it with
    `FoodReferenceDatabase`, and checks that the `aisle` column, the
    `open_food_facts_products_aisle_rank` index and the
    `AFTER UPDATE OF name, brand` trigger exist and that the content hash is
    gone.
*   `test/data/open_food_facts_repository_test.dart` (Modify): `searchLocal`
    with an Aisle keeps only that Aisle's name matches and keeps a barcode
    match from another Aisle; `keepOpenedProduct` on a bundled row that has
    an Aisle leaves the Aisle; a code that `lookupBarcode` newly stores from
    a live hit has no Aisle; `productsInAisle` returns an empty list when the
    database cannot be opened.
*   `test/features/nutrition/add_food_repository_test.dart` (Modify):
    `_RecordingOpenFoodFactsRepository.searchLocal` gains the
    `FoodAisle? aisle` parameter, so the file compiles; no new case.
*   `test/performance/performance_budgets_test.dart`,
    `performance_budget_thresholds.dart` and `README.md` (Modify):
    `_syntheticOpenFoodFactsLines` assigns Aisles as stated in
    [Performance](#performance); the test times the two reads stated there;
    the thresholds file gains the new constant, and the README a row for
    each read.
*   Server tests (Modify):
    *   `apps/server/test/open-food-facts-bundle.test.mjs` (step 4): the
        fixture helper `product()` gains `aisle = null` and writes it as the
        last key (`writeBundle` already writes the current format version);
        the format version 2 parse; rejection of a missing `aisle` key and of
        an unknown id; the sampled-line test checks `aisle`; `searchBundle`
        with an Aisle and no query lists it in order, with a query keeps only
        the Aisle's name matches, and keeps a barcode match from another
        Aisle; `FOOD_AISLES` and `FOOD_AISLE_LABELS` match the enum read from
        `apps/mobile/lib/domain/nutrition/food_aisle.dart`, taking the text
        between `enum FoodAisle {` and the first `;` and matching
        `/(\w+)\('([^']+)'\)/g`, as the Nutrient test reads `NutrientId`;
    *   `apps/server/test/agent-foods.test.mjs` (step 5): listing an Aisle
        with no `search`, in order; search within an Aisle, with a barcode
        match from another Aisle kept; `aisle` with no `source` uses Open
        Food Facts; `aisle` with `source=usda` throws
        `AgentPlatformSearchInvalidRequestError`; the `aisle` field on both
        sources. The existing tests that read `result.foods` are unchanged,
        because the return type is kept;
    *   `apps/server/test/agent-foods-routes.test.mjs` (step 5): the 422
        response and its body;
    *   `apps/server/test/agent-mcp.test.mjs` (step 5): the existing
        "search-platform-foods returns the same Open Food Facts body as REST"
        test gains an `aisle` case and the 422 case, with REST and MCP
        giving the same body;
    *   `apps/server/test/agent-skill.test.mjs` (step 5): `prn-code.mjs`
        passes `aisle`.

#### Pull request 2: the picker

*   **Precondition:** it starts after the phase 1 picker
    ([Unified Food Search](unified-food-search.md)) has merged, from `main`.
    It uses the phase 1 parts listed in [The picker](#the-picker).

##### 18. `lib/features/nutrition/repositories/add_food_repository.dart` (Modify)

*   **Scope:** app feature.
*   **Changes:** imports `aisleBrowseLimit` from `food_aisle.dart`;
    `browseAisle` on the interface and on `RepositoryAddFoodRepository`,
    calling `productsInAisle` for a blank query and
    `searchLocal(query, limit:, aisle:)` for a typed one, then
    `_openFoodFactsItems` with the `yourFoods` argument.

##### 19. `lib/features/nutrition/controllers/add_food_controller.dart` (Modify)

*   **Scope:** app feature.
*   **Changes:** `AddFoodPickerState.aisle` and `copyWith`'s `clearAisle`;
    `_aisle`; `openAisle` and `closeAisle`; and the changes to `_load`,
    `submitQuery`, `selectFilter` and `_reloadDeviceMatches` in the table in
    [The picker](#the-picker).

##### 20. `lib/features/nutrition/widgets/add_food_picker.dart` (Modify)

*   **Scope:** app feature.
*   **Changes:** `AddFoodPicker` becomes a `ConsumerStatefulWidget` with a
    `TextEditingController`; the Browse section; the Aisle view; the
    `PopScope`; closing the Aisle before a scanned barcode is looked up; the
    keys in [The picker](#the-picker). Every Aisle open or close (an Aisle
    row, the back button, the `PopScope`, a scanned barcode) clears the text
    controller first, as stated under "The widget" in
    [The picker](#the-picker).

##### 21. `docs/designs/SITEMAP.md` and this spec (Modify)

*   `unified-food-search.md`: no change. Its Future Improvements already
    link this spec.
*   This spec's Status becomes Current, and its SITEMAP row says so.

##### 22. Tests for pull request 2 (Modify)

*   `test/features/nutrition/add_food_repository_fakes.dart`: a new mixin,
    `NoAisleBrowsing`, whose `browseAisle` returns an empty list. Every fake
    `AddFoodRepository` mixes it in: in `nutrition_day_view_test.dart`,
    `_EmptyAddFoodRepository`, `_SingleFoodRepository` and
    `_BarcodeFoodRepository`; in `add_food_picker_test.dart`,
    `_StubAddFoodRepository`, `_TrackingAddFoodRepository`,
    `_DeferredAddFoodRepository`, `_EmptyAddFoodRepository`,
    `_OfflineOpenFoodFactsRepository` and `_OnlineAddFoodRepository`.
*   `test/features/nutrition/add_food_repository_test.dart`: `browseAisle`
    with a blank query (order and the 100 limit); with a typed query; Last
    Portions on Aisle rows.
*   `test/features/nutrition/add_food_picker_state_test.dart`:
    *   `openAisle` loads the Aisle; `closeAisle` restores the earlier
        filter's blank view with an empty query;
    *   a typed query while an Aisle is open calls `browseAisle`;
    *   submit in an Aisle makes no live request and returns `null`;
    *   `selectFilter` clears the Aisle;
    *   the bundle becoming `ready` reloads an open Aisle.
*   `test/features/nutrition/add_food_picker_test.dart`, the widget tests:
    *   **Where Browse shows:** in All (new user and returning user) and in
        the Open Food Facts filter; hidden while the bundle is not ready, in
        Your foods and USDA, and on a typed query.
    *   **The Aisle view:** the header and title; the hint "Search Snacks";
        the line "Showing the 100 most scanned. Search to find more." with
        100 rows and not with 99; "No foods match in Snacks."; no online row;
        the attribution footer.
    *   **The field:** opening and closing an Aisle clears the text on screen.
    *   **A scanned barcode** while an Aisle is open closes the Aisle before
        the lookup.
    *   **Back:** the back button, the system back and a barrier tap each
        close the Aisle and leave the sheet open.
    *   **Accessibility:** semantics labels and headers, 48 dp rows, and text
        scale 2.0 with no overflow.

## Verification Plan

*   **Pull request 1:** `pnpm ci:local mobile golden contract js sync
    workflow_lint` passes: the jobs that `apps/server/**` and
    `.github/workflows/ci.yml` trigger. The `js` and `sync` jobs need
    Docker. `golden` is listed to show that no vector changed.
*   **Pull request 2:** `pnpm ci:local mobile` passes.
*   **The tests** in items 17 and 22 pass, including the new
    `test/tool/aisle_pipeline_test.dart`, `test/tool/aisle_data_test.dart`
    and `test/data/food_reference_schema_upgrade_test.dart`.
*   **Kill and reopen.** The logging path does not change, so there is no new
    kill-and-reopen-mid-workout case. The killed-install case in
    `food_reference_database_test.dart` (item 17) covers being killed during
    an install.
*   **Checked by hand in step 3, and recorded in pull request 1's
    description**, because these are command-line behaviours with no unit
    tests:
    *   the builder refusing missing or stale labels (exit 1, no bundle, the
        "N products need labels" line) and `--aisle-input-only` (exit 0, no
        bundle, the shorter report);
    *   the labeller against the real server: model matching through
        `/api/tags`, a stopped and resumed run reusing the checkpoint,
        `--dev-only` writing no file, a wrong `--ollama` URL giving exit 69,
        and stopping the server mid-run (each product retried twice, then
        the stop after 10 unlabelled products in a row, exit 1);
    *   `sample` refusing stale labels (exit 1).
*   **Sync.** Not touched, so there is no sync simulation case.
*   **Pull request 1's description includes:**
    *   the builder's report: per-Aisle counts, counts per deciding step, no
        missing or stale labels, the dev and test measures, and the country
        split;
    *   the labeller's report;
    *   the labels header's model and digest.
*   **On a device (pull request 2):** a debug build with a fresh install of
    the version 2 bundle. The Browse section lists all 14 Aisles. Opening Snacks and
    searching "salt" shows only products in the Snacks Aisle. Back returns to
    Browse with the sheet open. This is checked on Android and iOS at text
    scale 1.0 and 2.0, in the light and dark themes.
