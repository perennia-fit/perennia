# Development

Getting the app and server running from source. Everything here works on an
ordinary developer machine — there is no shared infrastructure to be granted
access to, and no device lab.

## Prerequisites

| Tool | Version | Needed for |
|---|---|---|
| Flutter (stable) | Dart SDK ≥ 3.6 | The app |
| Node | see [`.node-version`](../.node-version) | Server, contract, tooling |
| pnpm | 9.15.4 (via `corepack enable`) | JS workspace |
| Docker | any recent | Postgres for the server tests only |

Docker is only required for the database-backed jobs. You can build, run, and
test the **app** without it.

## First run

```bash
corepack enable
pnpm install
flutter pub get
dart run melos bootstrap
```

## Running the app

```bash
cd apps/mobile
dart run build_runner build      # generate the Drift database code
flutter run
```

The app opens with **no server configured**, which is a supported state, not an
error: it is a complete offline logger with no account. Sign-in is only needed
for sync and the agent API.

To point a build at a server, inject it at build time:

```bash
flutter run --dart-define=PERENNIA_DEFAULT_SERVER_URL=http://10.0.2.2:3000
```

`10.0.2.2` is how the Android emulator reaches your host machine. On a physical
device, use your machine's LAN address. You can also leave the define off and
type the URL into the sign-in screen — the field exists precisely so a build is
never tied to one server.

## Building an APK

```bash
cd apps/mobile
flutter build apk --debug
```

The artifact lands in `apps/mobile/build/app/outputs/flutter-apk/`. Debug builds
are signed with your local debug keystore, which is all you need to install on
your own device.

## Test data

The app ships with no sample data, so a fresh install is empty. To see real
history (charts, records, the Today screen, prefill from last session), load
generated data onto a device or emulator running a **debug** build:

```bash
pnpm test-data                      # 12 weeks ending today, onto the only connected device
```

That writes four days of strength training a week, plus a weekend run, with
progression, deloads and the odd missed rep. It adds a body-weight trend and
logged meals, all against the bundled exercise library. Useful options:

| Option | Effect |
|---|---|
| `--weeks 26` | Length of history |
| `--seed 7` | Different but reproducible data; the same seed always gives the same history |
| `--end 2026-06-30` | Fix the window, for screenshots that don't change day to day |
| `--no-nutrition` | Training and body weight only |
| `--no-push` | Only write `apps/mobile/build/test-data/perennia.sqlite` |
| `--device SERIAL` | Choose a device when several are connected |

Loading **replaces the app's database on that device**. It works only on debug
builds (it uses `adb run-as`), so it can't touch a store install. The generator
lives in `apps/mobile/tool/test_data/` and writes through the app's own
repositories, so the file always matches the schema of your checkout. Regenerate
after a schema change rather than reusing an old file.

## Refreshing the Open Food Facts bundle

The app ships an offline bundle of Open Food Facts products,
`apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz`, built from Open Food
Facts' JSONL dump. Each product carries an Aisle, labelled when the bundle is
built. The design is in [open-food-facts.md](designs/open-food-facts.md), and the
Aisle steps in [food-aisles.md](designs/food-aisles.md). Refreshes are planned at
most once a quarter, with an app release, each in its own pull request.

A refresh is these runs, all from `apps/mobile`: the builder with
`--aisle-input-only`, the labeller, the second opinion, the review, then the
builder again. The labeller asks only about products that are new or whose
name, brand or last six Open Food Facts tags changed, so a refresh labels a
fraction of the bundle. If a step is skipped, the last build writes no bundle
and says which step to run.

1.  Download the dump. It is about 13 GB compressed and Open Food Facts replaces
    it daily, keeping no history, so keep your copy if you may need to rebuild
    the same bundle. Note its `Last-Modified` date; that is the dataset version.

    ```bash
    curl -sIL https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz | grep -i last-modified
    curl -L -C - -o openfoodfacts-products.jsonl.gz https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz
    ```

2.  Run the builder with `--aisle-input-only` (about 30 minutes). It writes
    `build/open_food_facts_aisle_input.ndjson` and a report, and no bundle:

    ```bash
    dart run tool/open_food_facts_bundle/build_bundle.dart --input <path to openfoodfacts-products.jsonl.gz> --dataset-version <YYYY-MM-DD> --aisle-input-only
    ```

    Read the dump section of its report. Check that:
    *   each country keeps a similar share of its eligible products. A
        country far below the others usually means Open Food Facts moved a
        field: the first build, reading only the legacy `nutriments`, kept 8
        products for the United Kingdom;
    *   the exclusions by reason, and the counts of products dropped for
        missing core nutrients or zero scans, are close to the last refresh's;
    *   "nutrients read from" shows how many products used `nutrition` and how
        many the legacy `nutriments`.

    Its last lines give the number of products whose label or second opinion
    is missing or stale: the work the next steps do.

3.  Label the new and changed products with Clef, served by
    [Ollama](https://ollama.com) (`ollama pull clef`). The run checkpoints every
    500 products, so it can be stopped and started again:

    ```bash
    dart run tool/open_food_facts_bundle/label_aisles.dart label --ollama http://localhost:11434
    ```

4.  Get a second opinion on the labels that are not confident. The first
    command writes `build/open_food_facts_aisle_second_opinion_input.ndjson`.
    Send it to a hosted model with any client you have, telling the model to
    treat each product's `state` as data, and save its answers as JSON lines of
    `{"code":"…","choice":"…"}`. Then take them in, naming the model:

    ```bash
    dart run tool/open_food_facts_bundle/label_aisles.dart second-opinion-input
    dart run tool/open_food_facts_bundle/label_aisles.dart second-opinion-apply --model <the model's name> --answers <path>
    ```

5.  Settle the edge cases, where the two models disagree, on the review page.
    It prints a local URL; answer up to 50 products, most scanned first, with an
    Aisle, `none` or `unsure`. Each answer is written to `aisle_overrides.csv`
    at once. `label_aisles.dart guide` prints the principles and the Aisle
    descriptions the page shows.

    ```bash
    dart run tool/open_food_facts_bundle/label_aisles.dart review
    ```

6.  Run the builder again, without `--aisle-input-only`. It writes the bundle
    and prints the full report. Check that:
    *   `labels missing or stale` and `second opinions missing or stale` are both
        0. Otherwise it writes no bundle, exits with status 1 and names the
        step to run;
    *   "products per Aisle" gives every Aisle some products, with counts close
        to the last refresh's, and "products per deciding step" shows how many
        Aisles came from an override, a confident label, or the two models
        agreeing;
    *   "products with an Aisle" is above the coverage floor (85%). The line says
        `BELOW THE FLOOR` when it is not, and the asset tests then fail; see
        [What CI checks](designs/food-aisles.md#what-ci-checks);
    *   the compressed bundle is under the 6 MB budget. The builder exits with
        an error when it is not.

7.  Run `flutter test test/data/open_food_facts_bundle_asset_test.dart
    test/tool/aisle_data_test.dart` from `apps/mobile`, then open the pull
    request with the bundle and the three data files under
    `tool/open_food_facts_bundle/` (`aisle_labels.ndjson`,
    `aisle_second_opinions.ndjson` and `aisle_overrides.csv`). Record the
    dataset version and paste both builder reports in its description.

### Changing Aisles without a refresh

To relabel the committed bundle without a new dump, after a change to the
Aisles, their descriptions or the question asked of the model, build from the
bundle itself and Open Food Facts' tags export
(`en.openfoodfacts.org.products.csv.gz`, about 1.5 GB, from
[Open Food Facts data exports](https://world.openfoodfacts.org/data)). Run
steps 2 to 7 with `--from-bundle` and `--tags-export` in place of `--input` and
`--dataset-version`:

```bash
dart run tool/open_food_facts_bundle/build_bundle.dart --from-bundle assets/seeds/open_food_facts_bundle.ndjson.gz --tags-export <path to en.openfoodfacts.org.products.csv.gz> --aisle-input-only
```

The products, their fields and the dataset version stay those of the committed
bundle; only the Aisles change. The first report gives the export's rows read
and skipped and the products found in it, in place of the dump section. A
product not in the export is labelled from its name and brand alone.

## Updating the Platform Library

The Platform Library is the seed
`apps/mobile/assets/seeds/platform_exercises.json`, generated from wger and
Workout.cool and filtered by a reviewed manifest. The server's copy is generated
from that seed. Never edit either by hand. The design is in
[platform-library-updates.md](designs/platform-library-updates.md).

1.  Edit the manifest, `tools/data/platform-exercise-review-decisions.json`.

2.  When the change retires an exercise, raise the manifest's top-level
    `retiredAt`. It must be later than `reviewedAt`, and it becomes the new
    records' `retired_at`, so the generator fails otherwise. A rename-only run
    leaves it alone.

3.  Check out wger at the pinned commit:

    ```bash
    git clone https://github.com/wger-project/wger.git <path>
    git -C <path> checkout ea78447
    ```

4.  Run the generators from the repository root:

    ```bash
    WGER_REPO=<path> node tools/generate-wger-platform-exercises.mjs
    node tools/generate-server-platform-exercise-seed.mjs
    ```

    The generator fetches every page of Workout.cool itself. Workout.cool is not
    pinned, so to rebuild the same seed later, set
    `WORKOUT_COOL_EXERCISES_PATH=<file>`, where the file is a JSON array of the
    records from every page of
    `https://workout.cool/api/exercises/all?page=N&limit=100` up to
    `pagination.totalPages`, kept outside the repository.

5.  Read the diff. Everything outside what the manifest changed should be
    unchanged except by key order, because Workout.cool can move between runs.

Two rules keep existing logs and devices correct, and the generator enforces
both against the previous seed:

*   **Keep an Exercise Type fixed for a live id.** A live id's `dimension_ids`
    must not change. For different dimensions, retire the id and add a new one.
*   **Never reuse a retired id.** The retired list is append-only, and an id
    cannot be both retired and live. A device that kept the retired exercise
    still holds that id as the user's own.

## Running the server

```bash
docker run -d --name perennia-dev-db \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=perennia -p 5432:5432 postgres:16-alpine

export DATABASE_URL=postgres://postgres:postgres@localhost:5432/perennia
export BETTER_AUTH_SECRET=$(openssl rand -hex 32)

pnpm --filter @perennia/server db:migrate
pnpm --filter @perennia/server start
```

It listens on `PORT`, defaulting to 3000. `GET /healthz` answers when the process
is up; `GET /readyz` also probes Postgres.

Sign-in with an email and password needs nothing further. Google and Apple
sign-in, push notifications, and tracker integrations each need their own
credentials — see [self-hosting.md](self-hosting.md) for the full set.

## The gate

```bash
pnpm ci:local            # everything
pnpm ci:local --changed  # only what your branch touched
pnpm ci:local --list     # job names
pnpm ci:local --skip-db  # skip the jobs that need Docker
```

`tools/ci-local.mjs` runs the same commands as
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml), job for job, so a green
run here means a green run on your pull request. When you change one, change the
other in the same commit.

Enable the pre-push hook so a red gate cannot leave your machine:

```bash
git config core.hooksPath tools/git-hooks
```

## Held dependencies

A few dependencies are pinned to an exact version rather than a range. A pin here
is deliberate and load-bearing — **a caret range cannot express "hold this back"**,
because `^1.4.0` still admits `1.5.2`, and pnpm keeps whatever the lockfile
already resolved. If you widen one of these back to a range, the update returns on
the next install.

| Package | Pinned at | Why |
|---|---|---|
| `@hono/zod-openapi` | `1.4.0` | `1.5.2` collapses type inference through the schema types it re-exports: every `.refine()` callback and MCP tool handler parameter becomes an implicit `any` (214 errors). Unpinning needs a migration, not a version bump. |
| `pg-boss` | `12.25.1` | It owns the job-queue tables and migrates them on start, so a bump changes a deployed database rather than just code. `deploy-config.test.mjs` asserts the exact version, which is the guard that makes an accidental bump fail loudly. Upgrade it deliberately, with the migration considered, and update that assertion in the same change. |

Dependabot proposes majors as their own pull requests rather than inside the
grouped routine updates, so a breaking release cannot block a dozen harmless ones.

## Working on the API

The server is the source of truth for the contract; the clients are generated.
After changing a route or schema:

```bash
pnpm --filter @perennia/contract generate
```

Commit the regenerated files with your change. CI fails if they drift, and the
diff is deliberate review surface: it shows what your change does to every client
before it merges. See [ARCHITECTURE.md](../ARCHITECTURE.md#the-contract-spine).

## Notes for Windows

- Keep the checkout **near the drive root**. Flutter generates deeply nested
  paths under `apps/mobile/ios/`, and a long checkout path pushes them past the
  260-character limit, which surfaces as a confusing `PathNotFoundException` from
  `flutter pub get`.
- After code generation, `git status` may list generated files as modified while
  `git diff` shows no change — a line-ending artefact. `git restore` clears it;
  do not commit it.
