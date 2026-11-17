# Releasing

How a Perennia version is cut, what a release produces, and the rules that keep
an installed app updatable without losing anyone's data.

## One version, three places

The app and the server share one version ([CHANGELOG.md](../CHANGELOG.md)),
stated in three places that must agree:

| Where | What it holds |
|---|---|
| `apps/mobile/pubspec.yaml` `version:` | `x.y.z+n`: the version name, then the build number (Android `versionCode`, iOS build number) |
| `apps/server/package.json` `version` | `x.y.z`, which the server reports on `GET /healthz` |
| `CHANGELOG.md` | a `## [x.y.z] - YYYY-MM-DD` section |

`node tools/check-release.mjs` checks that they agree. The `release_version` CI
job runs it on every pull request that touches one of them.

## Choosing the version

Perennia follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).
The app and the server share one version, so a release is numbered by the
largest change in either.

While the project is pre-1.0 (`0.y.z`):

| Bump | When the release contains any of these |
|---|---|
| **Minor** (`0.y.0`) | A user-visible feature or flow change; a new or changed REST operation, MCP tool, or contract field; a new Drift schema version or server migration; a sync or payload shape change; anything that breaks an agent or API client |
| **Patch** (`0.y.z`) | Only fixes that restore specified behaviour, copy and styling fixes, documentation, dependency bumps, or internal changes, with no schema, contract, or sync change |

From 1.0 on, the usual rules apply: **major** for a breaking change to the REST or
MCP contract, or for dropping a sync shape an installed app may still send;
**minor** for new features, operations, fields, or migrations that existing
clients keep working with; **patch** for fixes only.

Whatever the bump, the build number after `+` in `apps/mobile/pubspec.yaml` goes
up by one in every release and never resets (see
[Rules that keep installs updatable](#rules-that-keep-installs-updatable)).

### Keeping the changelog current

Every pull request that changes something a user, an agent, or a self-hoster can
notice adds a line under `## [Unreleased]` in [CHANGELOG.md](../CHANGELOG.md),
under `Added`, `Changed`, `Fixed`, or `Removed`. Write it for the person using the
app or the API, not for the code reviewer, and link the pull request. Docs-only,
test-only, and refactor-only pull requests add nothing.

The release pull request then only has to move those entries into the new
version's section and choose the bump from them.

## Cutting a release

1. Open a pull request that moves `## [Unreleased]` entries into a new
   `## [x.y.z] - YYYY-MM-DD` section and bumps both versions, choosing the
   bump as in [Choosing the version](#choosing-the-version). Raise the build
   number after `+` by one (see below).
2. Merge it to `main` once the gate is green.
3. Tag the merge commit on `main` and push the tag:

   ```bash
   git tag -a v0.1.0 -m "Perennia 0.1.0"
   git push origin v0.1.0
   ```

The tag runs [the release workflow](../.github/workflows/release.yml). It
re-checks the versions against the tag and refuses a tag that isn't on `main`.
It then publishes:

- the server image `ghcr.io/perennia-fit/perennia-server:x.y.z`, and moves `latest`
  to it;
- a GitHub Release whose notes are the CHANGELOG section.

**Every deployment and store build is cut from a release tag**, not from `main`.
A deployment pins the exact image version, and an app build is made from the
tagged commit. A merge to `main` therefore changes nothing that is running. Never
move or re-push a release tag: a deployment that pins it would silently change.

## Rules that keep installs updatable

An install of the app holds the user's only copy of local-only data. Android
installs an update over it, keeping that data, only when all three of these hold:

- **Same application ID** (`fit.perennia.app`). It is permanent.
- **Same signing certificate.** A release build refuses to build without the
  release signing key (`ANDROID_UPLOAD_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`), because a debug-signed release on a
  phone can never be replaced by a real one. For a throwaway release build on your
  own device, set `PERENNIA_ALLOW_DEBUG_SIGNED_RELEASE=true` with none of those set,
  and expect to uninstall it.
- **A higher build number.** Android refuses to install a lower `versionCode`
  over a higher one. Raise the number after `+` in every release that can reach a
  device, and never reuse or lower it, even when the version name restarts or a
  build was only installed by hand.

Data also has to survive the upgrade itself:

- **Migrations only move forward from the first release.** Once a version is
  tagged, its Drift schema (`AppDatabase.schemaVersion`) and its server migrations
  (`apps/server/drizzle/`) are history. A later change adds a migration from
  them. It never edits a released migration, resets the schema, or relies on a
  user reinstalling. Every Drift schema version from the first release on has
  a committed snapshot, and CI checks upgrades from each one (see
  [Drift schema snapshots](#drift-schema-snapshots)).
- **The server stays compatible with installed apps.** Nothing forces an app
  update, so a server release must keep accepting what older app versions still
  installed send. Change sync and API shapes by expanding first (accept old and
  new), and remove the old shape only once no supported app sends it.

### Drift schema snapshots

Release 0.0.1 ships `AppDatabase.schemaVersion` 62. Every version from 62 on
has a committed snapshot of its schema in
`apps/mobile/drift_schemas/app_database/drift_schema_v<N>.json`, and
`apps/mobile/test/generated_migrations/app_database/` holds the test helpers
drift_dev generates from them. `test/data/schema_snapshot_migration_test.dart`
builds a database at each snapshot, upgrades it with the app's real
`MigrationStrategy`, and checks the result against the current snapshot. It also
checks that rows written at v62 survive to the current version, and that a fresh
install matches the current snapshot.

When you bump `schemaVersion` to N, from `apps/mobile`:

1. Write the `if (from < N)` migration step and bump `schemaVersion`, then
   regenerate the Drift code as usual (`dart run build_runner build`).
2. Dump the new snapshot. It analyzes the whole database library, so expect it
   to take a few minutes:

   ```bash
   dart run drift_dev schema dump lib/data/local/app_database.dart drift_schemas/app_database/
   ```

3. Regenerate the test helpers:

   ```bash
   dart run tool/drift_schema_snapshots.dart
   ```

4. Run `flutter test test/data/schema_snapshot_migration_test.dart`. If the
   migration moves or rewrites data, add a check there that the affected rows
   come through intact.
5. Commit the snapshot and the regenerated helpers with the schema change.

The mobile job's "Fail on a missing Drift schema snapshot" step fails when
`schemaVersion` has no snapshot or the helpers are stale, and the fresh-install
test fails when the schema changed without a bump.

A snapshot of a version that has been in a release tag is never re-dumped or
edited: if dumping would change it, the schema changed without a bump. A
version that has not been released yet can be re-dumped while it is still
being worked on.

`FoodReferenceDatabase` has no snapshots. It holds rebuildable reference data,
and its upgrade drops and reinstalls everything rather than migrating rows.
