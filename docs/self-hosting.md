# Self-hosting

Running your own Perennia server. The app can point at any server — that is not a
concession, it is the design: a build ships with no default server, so you enter
your own and nothing about the app treats yours as second class.

What self-hosting gives you: accounts, sync across your devices, and the full
agent API and MCP surface. It is developer-grade — you will be operating a
Postgres database and a container.

## What you need

- A host that can run a container, reachable over HTTPS.
- Postgres 16.
- A domain or stable address for the server. Sign-in providers need to redirect
  back to it.

## Build and run

The image builds from the repository root:

```bash
docker build -t perennia-server .
```

```bash
docker run -d --name perennia \
  -p 3000:3000 \
  -e DATABASE_URL="postgres://user:password@host:5432/perennia" \
  -e BETTER_AUTH_SECRET="$(openssl rand -hex 32)" \
  -e PUBLIC_SERVER_URL="https://perennia.example.com" \
  perennia-server
```

Apply migrations against a new database before first start:

```bash
pnpm --filter @perennia/server db:migrate
```

Some background work (retention, scheduled imports) runs in a separate worker
process from the same image, started with `node dist/worker.js`. A single-user
deployment can skip it; scheduled jobs simply will not run.

### Health

| Endpoint | Meaning |
|---|---|
| `GET /healthz` | The process is up |
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
account settings, and give it to your agent as a bearer token. The tools and
operations are identical everywhere — there is no hosted-only capability.

## Operating notes

- **Back up Postgres.** It holds everything the server knows. The app keeps its
  own replica, so a device can restore a lost account's data by syncing up, but
  do not rely on that as a backup strategy.
- **Migrate before you deploy a new image.** Run `db:migrate` against the new
  version first; the server does not migrate on boot.
- **Your data goes nowhere else.** A self-hosted deployment contacts no
  infrastructure belonging to the maintainers, and the app contains no analytics
  in any mode.
