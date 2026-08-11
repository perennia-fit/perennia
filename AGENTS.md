# AGENTS.md — Perennia

Entry point for AI coding agents working in this repository. Read this file first,
then follow the pointers below before writing any code or docs.

## What this project is

An **open-source, AI-native workout logger**: a Flutter mobile app (Android + iOS)
that is fully functional offline with no account, with optional sync to a TypeScript
server where AI agents are first-class API clients. The logging model and navigation
are deliberately modeled on FitNotes (https://www.fitnotesapp.com/help_overview/) —
**similar UI/UX, not a clone**: FitNotes is the reference map for how users navigate
and log, never a feature-parity contract or a visual asset source.

## Required reading (in this order)

1. [CONTEXT.md](CONTEXT.md) — the ubiquitous language. Use these exact terms in code,
   UI copy, API surfaces, and docs. If a concept isn't there, propose a definition
   before inventing a name.
2. [DESIGN.md](DESIGN.md) — the visual design system, in the Stitch design-md format
   (https://stitch.withgoogle.com/docs/design-md/overview/). **The source of truth
   for all UI styling.** Read it before building or modifying any screen; its YAML
   front matter holds the normative tokens, its prose explains how to apply them.
3. [CONTRIBUTING.md](CONTRIBUTING.md) — how to get a change merged: the CLA gate,
   running the CI gate locally, and what a reviewable pull request looks like.

The invariants below are the load-bearing rules. They are properties of the
shipped code, not aspirations — treat a violation as a bug even when the feature
works.

## Current state

Pre-1.0 and unreleased. The offline logger, the sync server, and the agent
REST/MCP surface are all implemented across four authored domains (training,
nutrition, protocols, and the plan layer). The app is built offline-first: it is
fully usable with no account and no server, and sync is optional. Nothing has
shipped to an app store yet.

## Tech stack — settled; do not substitute

| Layer | Choice |
|---|---|
| Mobile client | Flutter (Android + iOS), no web/desktop client planned |
| Client data | Drift (SQLite), reactive stream queries |
| Client state | Riverpod; Widgets → Controllers → Repositories → Drift/HTTP. Repositories are the only layer that touches storage or network |
| Charts | fl_chart |
| Server | TypeScript (Hono/Fastify), OpenAPI-first, Postgres, Better Auth |
| Agent surface | REST (OpenAPI) + in-process MCP server |

## Non-negotiable invariants

These come from ADRs and §1.1/§4 of the high-level design. Violating one is a bug
even if the feature "works":

- **A Workout is a session**, not a day-bucket. Training Day is a derived view.
- **Sets are self-describing** — values + units stored as entered. Exercise Type is
  an input template, never a schema constraint; changing it never touches history.
- **Derived analytics (PRs, e1RM, volume, stats) are computed, never stored or
  synced.** No "recalculate" repair paths; caches invalidate mechanically.
- **User-facing delete = archive** for exercises and categories. History survives.
  No cascading deletes, ever.
- **Restore/import is merge-only.** No destructive restore path exists.
- **Local writes never block on the network.** Set save confirms within one frame.
- **Sync is silent LWW with recoverable losers** via the Activity Log. No conflict
  dialogs.
- **Validation is one shared two-tier module** (hard-reject impossible, soft-warn
  improbable), identical for UI and agent API, golden-vectored in both languages.
- **No behavioral analytics, ever.** Crash reporting opt-in, default off.

## UI/UX model — FitNotes as the navigation reference

The screenshots throughout the FitNotes help pages
(https://www.fitnotesapp.com/help_overview/ and its sub-pages) are the initial
reference for screen layout and flow. Adopt the *ergonomics*; restyle per DESIGN.md.

### Screen map

- **Today root** — the daily authored-log dashboard: date header with swipe/arrow
  navigation, `Training | Nutrition` day views, contextual Routine access, and one
  **Log** action for Workout, Food, and discreet Supplement logging. Training renders
  the exercise log as cards (exercise name + set rows of value × reps), with colored
  edge bars for groups. Root navigation is **Today | Progress | Library** —
  organized by user intent, not by data type.
- **Progress root** — review and monitoring: training progress, Body Tracker's
  curated manual-entry view, and the wider Health Metrics explorer.
- **Library root** — reusable plans and catalogues grouped by authored domain;
  Routines live under Training and the discreet Compound list under Supplements.
- **Training Screen** — per-exercise set entry, three tabs: **Track | History |
  Graph**. Track = large value fields with ± stepper buttons, prefilled from the
  previous session; **Save/Clear** buttons that become **Update/Delete** when an
  existing set is selected; set list below with per-set comment icons, complete
  checkboxes, and a trophy marker on PRs. App bar gives rest timer, records, and
  exercise info.
- **Navigation Panel** — drawer (logo tap or edge swipe) listing the current
  workout's exercises with set counts; jump, reorder (press-and-hold), add
  exercise, manage superset groups; auto-advance to the next group member after a
  save.
- **Exercise List** — categories first, then exercises; search; favorites; "+" to
  create. (The FitNotes title-dropdown routine picker is superseded by the
  Routines picker.)
- **Exercise Overview** — the aggregator: history, graphs, records, stats, goals
  for one exercise. The navigational glue — reachable from workout, list, calendar.
- **Calendar** — month view with category-colored dots (+ list view); filters by
  category/exercise with thresholds.
- **Routines & Workout Templates** — Home "Up next"
  suggestion cards computed from Cadences; picker sheet grouped Today / Routines /
  All Templates; one-tap **materialize** into a new Workout (Template Link recorded);
  Template editor (exercises, per-entry notes, Prescriptions, groups + rounds) and
  Routine editor (membership + Cadence slot layout) as separate surfaces; capture
  ("save workout as template") and the Finish-time "update the template?" prompt.
- **Workout Tools (interval/rest timer, 1RM/set/plate calculators) and Settings** —
  secondary surfaces reached contextually or through **Account & app**, not extra
  root destinations.

### UX rules of thumb

- **Logging a repeat set must take ≤ 2 taps** (open exercise → Save). Prefill from
  last session is what makes this possible — preserve it in every redesign.
- **The gym floor is the context**: one-handed reach, ≥ 48 dp touch targets, big
  numerals readable at arm's length, instant local saves, no spinners on the
  logging path.
- Set entry fields adapt to the exercise's dimension set (load/reps/duration/
  distance — any combination, including completion-only).
- Color is never the sole signal (category colors are always paired with text);
  WCAG AA contrast in both themes.
- No onboarding wizards, no sample data; the empty Home Screen's CTA is the
  onboarding.

## Working conventions

- **Terminology discipline**: code identifiers, UI copy, and API fields use
  CONTEXT.md terms (e.g. `Workout` not `Session`, `archive` not `delete`,
  Dimension vs Annotation).
- **Document decisions in the code**: when a non-obvious choice is load-bearing,
  the reasoning belongs in the docstring next to it, not in a tracker or a
  document a reader has to go find.
- **UI work**: tokens and component rules come from DESIGN.md — don't hardcode
  colors, radii, or spacing in widgets; map DESIGN.md tokens to the Flutter theme
  and consume them from there.
- **Test strategy**: golden vectors
  for analytics (Dart + TS must agree), repositories against real in-memory
  SQLite, sync simulation tests, kill-and-reopen mid-workout as a standing
  scenario.
- Do not commit FitNotes assets (screenshots, icons, names of their image files).
  Reference their help pages by URL only.

## CI and PR workflow

Hosted CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs on every
pull request and is the authoritative gate. Jobs are path-filtered, so a change
only pays for the checks it can actually break.

### Running the gate locally

[tools/ci-local.mjs](tools/ci-local.mjs) (`pnpm ci:local`) runs the **same
commands** as `ci.yml`, job-for-job, so a green run here means a green run on the
pull request. When you change `ci.yml`, update `ci-local.mjs` in the same commit
so the two never drift.

- `pnpm ci:local` — full gate; `pnpm ci:local mobile js` — named jobs;
  `pnpm ci:local --changed` — only jobs whose paths changed vs `main`;
  `--list`, `--skip-db` as documented in the file header.
- DB jobs (`js`, `sync`) need Docker running — they spin up an ephemeral
  `postgres:16-alpine` (host port 55432, auto-removed) and force `CI=true` to
  match the hosted environment.
- `workflow_lint` self-skips where actionlint is not installed; hosted CI covers
  that gap.

### Creating a PR

Run the gate locally and make it green first: `pnpm ci:local --changed` (or the
full gate for a wide change). A `pre-push` hook (`tools/git-hooks/pre-push`,
enabled with `git config core.hooksPath tools/git-hooks`) runs this automatically
and blocks red pushes; bypass it deliberately with `git push --no-verify`.

### Gotcha — Windows codegen churn

After the `mobile`/`contract` jobs run code generation, `git status` may show
generated files (`*.g.dart`, `openapi.json`, `agent-client.ts`, the Dart API
client) as modified while `git diff` shows no content change — an mtime/CRLF
artifact, not real drift. The gate's own `git diff --exit-code` checks still pass;
`git restore` clears the noise. Don't commit those phantom changes.
