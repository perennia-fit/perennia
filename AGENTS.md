# AGENTS.md — Perennia

Entry point for AI coding agents working in this repository, and a fast
orientation for humans. Read this first, then the pointers below, before writing
any code or docs.

If you change one thing based on this file, make it this: **the invariants below
are properties of the shipped code, not aspirations.** Violating one produces a
bug that looks like a working feature, which is the expensive kind — and the kind
review is worst at catching.

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
3. [ARCHITECTURE.md](ARCHITECTURE.md) — how the pieces fit: the app's layering,
   the contract spine and what is generated from what, the sync model, and the
   shared validation module. Deliberately coarse; it describes what stays true.
4. [CONTRIBUTING.md](CONTRIBUTING.md) — how to get a change merged: the CLA gate,
   running the CI gate locally, and what a reviewable pull request looks like.
5. [docs/development.md](docs/development.md) — building and running the app and
   server from source, and the gate.
6. [docs/designs/SITEMAP.md](docs/designs/SITEMAP.md) — the index of design specs.
   Before changing an area, read the spec that covers it; it is the contract the
   code was built against (see [Development methodology](#development-methodology--spec-driven)).

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

These were settled before this repository's design record began, and every
design spec must preserve them. Violating one is a bug even if the feature
"works":

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
  navigation, `Training | Nutrition | Protocols` day views, contextual Routine access,
  and one **Log** action for Workout, Food, and Dose. Protocols shows the day's
  planned and logged doses behind its lock, and a device setting hides the tab for
  users who want it out of sight. Training renders
  the exercise log as cards (exercise name + set rows of value × reps), with colored
  edge bars for groups. Root navigation is **Today | Progress | Library** —
  organized by user intent, not by data type.
- **Progress root** — review and monitoring: training progress, Body Tracker's
  curated manual-entry view, and the wider Health Metrics explorer.
- **Library root** — reusable plans and catalogues grouped by authored domain;
  Routines live under Training, and Protocols and Compounds under Protocols.
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
- **Document decisions where they bite**: a feature's intent, scope, and rejected
  alternatives live in its design spec under `docs/designs/`. A load-bearing
  choice at one code site still gets its reasoning in the docstring next to it —
  a reader of that line should not have to go find the spec to avoid breaking it.
- **UI work**: tokens and component rules come from DESIGN.md — don't hardcode
  colors, radii, or spacing in widgets; map DESIGN.md tokens to the Flutter theme
  and consume them from there.
- **Test strategy**: golden vectors
  for analytics (Dart + TS must agree), repositories against real in-memory
  SQLite, sync simulation tests, kill-and-reopen mid-workout as a standing
  scenario.
- Do not commit FitNotes assets (screenshots, icons, names of their image files).
  Reference their help pages by URL only.

## Development methodology — spec-driven

Non-trivial changes are designed before they are built, using the
[Elephant-Goldfish Model](https://github.com/google/elephant-goldfish-model)
(EGM). The idea in one paragraph: the agent that discussed a feature with you
(the **Elephant**) has too much context to judge its own spec — it fills gaps
from memory and approves its own assumptions. So the spec is written to stand on
its own, and then reviewed by fresh subagents (the **Goldfish**) that see only the
document and the code. If a Goldfish can't implement from the spec without
guessing, the spec isn't done. A human approves it; then the code is built
against it; then the spec stays in the tree as the record of why the code is the
way it is.

EGM artifact directory: .egm/

(That line is read by the EGM skills: briefs, drafts, and review reports go to
`.egm/`, which is gitignored. Only the finished spec is committed.)

### When a spec is required

Use judgment; the process exists to catch expensive mistakes, not to tax small
ones. Write a spec first when a change does any of these:

- touches one of the [non-negotiable invariants](#non-negotiable-invariants), or
  could plausibly be read as bending one;
- changes the Drift schema, the sync protocol, or anything that merges data
  (import, restore, conflict handling);
- adds or changes an API operation, MCP tool, or the contract (the agent surface
  must get the same operation the app does);
- changes a validation rule or an analytics computation (anything golden-vectored);
- introduces a domain concept that needs a new [CONTEXT.md](CONTEXT.md) term;
- adds a screen or changes a logging flow on the gym-floor path.

Skip it for bug fixes that restore specified behavior, refactors with no
behavior change, dependency bumps, copy and styling fixes within DESIGN.md, and
test-only changes. If a "small fix" turns out to need a decision nobody has made,
stop and write the spec.

### The loop

| Step | Command (Claude Code) | Output |
|---|---|---|
| 1. Brainstorm | `/egm:egm-brainstorm` | `.egm/concepts_brief.md` — the problem, stress-tested by a Goldfish swarm |
| 2. Draft | `/egm:egm-draft` | `docs/designs/<feature>.md`, written section by section with your approval at each gate |
| 3. Review | `/egm:egm-review docs/designs/<feature>.md` | Goldfish reports in `.egm/`: zoom-out (YAGNI, reuse), comprehension, design critique, implementation readiness |
| 4. Resolve | `/egm:egm-resolve` (offered by review) | Findings fixed or contested in the spec. Take what's useful; review is deliberately noisy |
| 5. Spec PR | — | A pull request with the spec and its SITEMAP entry, reviewed by a human |
| 6. Implement | — | Code built against the merged spec, in its own pull request |
| 7. Drift | `/egm:egm-drift-report docs/designs` | `.egm/<date>_DRIFT_REPORT.md`; reconcile by fixing the code or the spec — a human picks which |

Other harnesses use the same skills without the `egm:` prefix; install
instructions for Codex, Antigravity, and others are in the EGM README. The order
is a default, not a ritual: skip brainstorm when the problem is already clear,
re-run review after a large revision, go back to the spec when implementation
goes wrong.

### What a Perennia spec must contain

Start from the EGM template (the draft skill applies it): Overview, Problem,
Goals / Non-Goals, Open Questions, Critical User Journeys (Given / When / Then),
Technical Plan, Alternatives Considered, Non-Functional Requirements, Detailed
Implementation Plan, Verification Plan. On top of that, every spec here must:

- **Link [CONTEXT.md](CONTEXT.md), [ARCHITECTURE.md](ARCHITECTURE.md), and this
  file**, plus [DESIGN.md](DESIGN.md) for UI work. Goldfish reviewers read files
  the spec links and nothing else of the project's conventions — they run without
  CLAUDE.md, AGENTS.md, or conversation history. What the spec doesn't link, they
  don't know.
- **Name the invariants it touches** and say how each is preserved. "None" is a
  valid answer only if it's true.
- **Use CONTEXT.md terms**, and list any new term with its proposed definition.
  The CONTEXT.md change lands in the implementation pull request.
- **State the agent-surface consequence** of any app capability: the REST
  operation, the MCP tool, and what the contract diff will show.
- **State the validation and analytics consequence**: which rules change, which
  tier (hard reject / soft warn), and which golden vectors cover it.
- **Verify with the gate.** The Verification Plan names the `pnpm ci:local` jobs
  that must pass and the tests to add — repositories against in-memory SQLite,
  sync simulation, kill-and-reopen mid-workout where logging is involved,
  accessibility for screens.
- **Be self-contained and publishable.** This repository is public. A spec must
  not link to, quote, or depend on unpublished planning documents; if earlier
  reasoning matters, restate it in the spec.

Specs don't contain implementation code. Signatures, schemas, and pseudocode are
fine. The Detailed Implementation Plan lists every file to create or modify and
why, and leaves the implementer **no design decisions** — that's the bar
implementation-readiness review checks.

### Where specs live

- `docs/designs/<feature>.md` — one spec per feature or subsystem change, with an
  Author / Status / Date header. Status moves **Draft → In Review → Approved →
  Current** (implemented and matching the code), or **Superseded** with a link to
  its replacement. Specs are living: when the behavior changes, the spec changes in
  the same pull request.
- [docs/designs/SITEMAP.md](docs/designs/SITEMAP.md) — the index. The draft skill
  registers new specs there; check it did.

### Implementing against a spec

- Build what the merged spec says. The Detailed Implementation Plan is the scope:
  don't add what it doesn't list, and don't skip what it does.
- If implementation needs a decision the spec doesn't make, or shows the spec is
  wrong, **stop and update the spec** (a small follow-up to the spec, or in the
  implementation pull request with the change called out) instead of deciding
  silently in code. A spec that no longer matches the code is drift, and drift
  misleads the next agent.
- Link the spec from the implementation pull request, and set its Status to
  **Current** in that pull request once the code matches it.

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
  `postgres:16-alpine` (named per run, on a Docker-assigned loopback port,
  auto-removed) and force `CI=true` to match the hosted environment. Runs in
  parallel worktrees get separate containers and don't collide.
- `workflow_lint` self-skips where actionlint is not installed; hosted CI covers
  that gap.

### Creating a PR

A change that needs a spec goes in two pull requests: first the spec
(`docs/designs/<feature>.md` + its SITEMAP entry, reviewed on its own), then the
implementation, linking the merged spec. Don't fold an unreviewed spec into the
implementation pull request — the point is that a human agrees on the design
before code makes it expensive to change. Everything else is one pull request.

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
