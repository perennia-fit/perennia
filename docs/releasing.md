# Releasing

How a Perennia version is cut, what a release produces, and the rules that keep
an installed app updatable without losing anyone's data.

## Rules that keep installs updatable

An install of the app holds the user's only copy of local-only data, so data
has to survive every upgrade:

- **Migrations only move forward from the first release.** Once a version is
  tagged, its Drift schema (`AppDatabase.schemaVersion`) and its server migrations
  (`apps/server/drizzle/`) are history. A later change adds a migration from
  them. It never edits a released migration, resets the schema, or relies on a
  user reinstalling.

### Drift schema snapshots

Release 0.0.1 shipped `AppDatabase.schemaVersion` 62. Every version from 62 on
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
