# Third-party data

Perennia's code is licensed under the AGPL-3.0 ([LICENSE](LICENSE)). The
datasets the repository ships are licensed separately, by their own terms, and
those terms are listed here.

| Dataset | File | Licence | Attribution required | Licence file |
| :------ | :--- | :------ | :------------------- | :----------- |
| Open Food Facts bundle | `apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz` | [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/); contents [DbCL 1.0](https://opendatacommons.org/licenses/dbcl/1-0/) | Yes: "Contains information from Open Food Facts, made available under the ODbL 1.0", with a link to [Open Food Facts](https://world.openfoodfacts.org/). The derived bundle and the tool that builds it (`apps/mobile/tool/open_food_facts_bundle/build_bundle.dart`) stay available under the ODbL, as do the three Aisle data files in `apps/mobile/tool/open_food_facts_bundle/` that are part of the derived database: `aisle_labels.ndjson`, made by the labeller `label_aisles.dart` with the Clef decision model; `aisle_second_opinions.ndjson`, a second opinion from Claude Haiku (`claude-haiku-5-5`); and `aisle_overrides.csv`, a person's answers. | [`open_food_facts_bundle.LICENSE.md`](apps/mobile/assets/seeds/open_food_facts_bundle.LICENSE.md) |
| USDA FoodData Central seed | `apps/mobile/assets/seeds/usda_foods.json` | Public domain ([CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)) | No. The app credits [USDA FoodData Central](https://fdc.nal.usda.gov/) as the source. | None |
| Platform Exercise Library | `apps/mobile/assets/seeds/platform_exercises.json` | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) | Yes: the sources and per-record attribution listed in its licence file. | [`platform_exercises.LICENSE.md`](apps/mobile/assets/seeds/platform_exercises.LICENSE.md) |
