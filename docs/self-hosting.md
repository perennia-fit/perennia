# Self-hosting

Running your own Perennia server. The app can point at any server — that is not a
concession, it is the design: a build from source ships with no default server, so
you enter your own and nothing about the app treats yours as second class. (The
app from the app stores is built with the Official Service,
`https://api.perennia.fit`, as its default; you can still enter your own server's
URL on its sign-in screen.)

What self-hosting gives you: accounts, sync across your devices, and the full
agent API and MCP surface. It is developer-grade — you will be operating a
Postgres database and a container.

## What you need

- A host that can run a container, reachable over HTTPS.
- Postgres 16.
- A domain or stable address for the server. Sign-in providers need to redirect
  back to it.

## Get the image

Each release publishes the server image to the GitHub Container Registry as
`ghcr.io/perennia-fit/perennia-server:<version>` (for example `0.1.0`), plus
`latest` for the newest release. Pin the exact version: it never changes, so you
upgrade when you choose to, and `/healthz` tells you which one is running.

Or build it yourself from the repository root, at a release tag:

```bash
docker build -t perennia-server .
```

## Run

```bash
docker run -d --name perennia \
  -p 3000:3000 \
  -e DATABASE_URL="postgres://user:password@host:5432/perennia" \
  -e BETTER_AUTH_SECRET="$(openssl rand -hex 32)" \
  -e PUBLIC_SERVER_URL="https://perennia.example.com" \
  ghcr.io/perennia-fit/perennia-server:0.1.0
```

The server applies any pending database migrations on startup, before it
serves requests, so a new database needs no separate step.

Some background work (retention, scheduled imports) runs in a separate worker
process from the same image, started with `node dist/worker.js`. A single-user
deployment can skip it; scheduled jobs simply will not run.

### Health

| Endpoint | Meaning |
|---|---|
| `GET /healthz` | The process is up, and which release it runs (`version`) |
| `GET /readyz` | The process is up **and** Postgres answers |

Point your platform's health check at `/readyz`.

## Configuration

### Required

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | Postgres connection string |
| `BETTER_AUTH_SECRET` | Signing secret for sessions. Generate a random 32-byte value and keep it stable — rotating it signs everyone out. (`AUTH_SECRET` is accepted as an alias.) |
| `PUBLIC_SERVER_URL` | The server's public origin, used to build OAuth redirect URIs. (`BETTER_AUTH_URL` is accepted as an alias.) |

### Optional

| Variable | Purpose |
|---|---|
| `PORT` | Listen port. Defaults to `3000`. |
| `BETTER_AUTH_TRUSTED_ORIGINS` | Comma-separated additional origins allowed to authenticate. |
| `SERVER_CRASH_REPORTING_ENABLED`, `SERVER_CRASH_REPORTING_DSN` | Server-side crash reporting. Off unless you turn it on. |

Email and password sign-in works with nothing beyond the required variables.

### Sign in with Google or Apple

Register the redirect URI with the provider, then supply the credentials:

- Google: `${PUBLIC_SERVER_URL}/api/auth/callback/google` —
  `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`
- Apple: `${PUBLIC_SERVER_URL}/api/auth/callback/apple` —
  `APPLE_OAUTH_CLIENT_ID`, `APPLE_OAUTH_CLIENT_SECRET`

On the server, `GOOGLE_OAUTH_CLIENT_ID` is your Google **Web** client. The
server checks every Google ID token against it.

The app ships with no Google identity, so a build that should offer Google
sign-in needs your client IDs compiled in. For iOS, create an **iOS** OAuth
client for your bundle identifier in the same Google Cloud project, then build
with both IDs:

```bash
flutter build ipa \
  --dart-define=GOOGLE_OAUTH_CLIENT_ID=<ios-client-id>.apps.googleusercontent.com \
  --dart-define=GOOGLE_OAUTH_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

The app-side `GOOGLE_OAUTH_CLIENT_ID` is the iOS client. A build phase derives
Google's callback URL scheme (`com.googleusercontent.apps.<id>`) from it and
registers it in the built `Info.plist`, so there is nothing to edit in Xcode.
`GOOGLE_OAUTH_SERVER_CLIENT_ID` is the Web client, so the ID token is issued
for your server. If you leave both out, the build still succeeds and the app
shows Google sign-in as not configured. Email and Apple sign-in keep working.

### Push notifications and tracker integrations

Optional, and each needs its own credentials: `FCM_*` for Android push, `APNS_*`
for iOS push, `GARMIN_*` for the Garmin integration. Leave them unset and those
features stay dormant — nothing else degrades.

## Connecting the app

Install or build the app, open it, and enter your server's URL on the sign-in
screen. Or bake it into your own build:

```bash
flutter build apk --dart-define=PERENNIA_DEFAULT_SERVER_URL=https://perennia.example.com
```

## Agents

Your deployment exposes the same agent surface as any other: the REST API under
`/agent`, and an MCP server at `/mcp`. Create an agent key in the app under
account settings, and give it to your agent as a bearer token, with your server's
URL as the server URL (for the skill in `agent-skills/perennia`, that is
`PRN_BASE_URL`). The tools and
operations are identical everywhere — there is no hosted-only capability.

## Operating notes

- **Back up Postgres.** It holds everything the server knows. The app keeps its
  own replica, so a device can restore a lost account's data by syncing up, but
  do not rely on that as a backup strategy.
- **Upgrading migrates the database.** A newer image applies its migrations
  when it starts, and migrations only move forward, so back up before you
  upgrade. Moving back to an older image after that is not supported.
- **Your data goes nowhere else.** A self-hosted deployment contacts no
  infrastructure belonging to the maintainers, and the app contains no analytics
  in any mode.
