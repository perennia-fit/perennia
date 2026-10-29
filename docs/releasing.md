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

## Cutting a release

1. Open a pull request that moves `## [Unreleased]` entries into a new
   `## [x.y.z] - YYYY-MM-DD` section and bumps both versions. Raise the build
   number after `+` (see below).
2. Merge it to `main` once the gate is green.
3. Tag the merge commit on `main` and push the tag:

   ```bash
   git tag -a v0.0.1 -m "Perennia 0.0.1"
   git push origin v0.0.1
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
  user reinstalling.
- **The server stays compatible with installed apps.** Nothing forces an app
  update, so a server release must keep accepting what older app versions still
  installed send. Change sync and API shapes by expanding first (accept old and
  new), and remove the old shape only once no supported app sends it.
