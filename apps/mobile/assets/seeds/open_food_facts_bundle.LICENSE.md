# Open Food Facts Bundle Data License

SPDX-License-Identifier: ODbL-1.0

This file applies to `open_food_facts_bundle.ndjson.gz`, the offline Open Food
Facts bundle shipped with the app. The application source code in the rest of
the repository is licensed separately by the repository root `LICENSE`
(AGPL-3.0).

## Source and licences

The bundle is a derived database of Open Food Facts
(https://world.openfoodfacts.org/), made available under the Open Database
License (ODbL) 1.0: https://opendatacommons.org/licenses/odbl/1-0/

Individual contents of the database are made available under the Database
Contents License (DbCL) 1.0: https://opendatacommons.org/licenses/dbcl/1-0/

Contains information from Open Food Facts, made available under the ODbL 1.0.

## How it was derived

The bundle was produced from Open Food Facts' JSONL data dump
(https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz) by
`apps/mobile/tool/open_food_facts_bundle/build_bundle.dart`, which is the method
used to derive it. The dump's date is the `datasetVersion` in the bundle's first
line. The tool keeps, for Australia, the United States, the United Kingdom,
Canada and New Zealand, up to 10,000 scanned products each with a name and
known energy, protein, carbohydrate and fat; maps each product's name, first
brand, serving and package size, nutrition per 100 g or ml (skipping values
Open Food Facts estimated from the ingredient list), change date and scan
count; and writes them as JSON lines. Products with implausible values per
100 g or ml are left out.

This derived database is offered under the same ODbL 1.0 terms.

## Disclaimer

Values come from Open Food Facts contributors and may be incomplete or wrong.
Check the label. Not for medical use.
