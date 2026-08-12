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
