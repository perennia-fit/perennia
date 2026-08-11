# Contributing to Perennia

Thanks for considering a contribution. This document covers the contributor licence
agreement, how to get a change through the gate, and the conventions that keep the
codebase coherent.

## Contributor licence agreement

**Every contribution requires a signed CLA, from the first one.** When you open your first
pull request, [CLA Assistant](https://cla-assistant.io/) comments with a link. Signing is a
single click with your GitHub account, and you only do it once.

The full text is in [CLA.md](CLA.md). In short: **you keep the copyright to your work**,
and you grant a licence broad enough that your contribution can be sublicensed and
relicensed.

### Why the CLA is broader than the project's own licence

We think you deserve a straight answer rather than boilerplate, because the grant is
genuinely asymmetric and you should decide with that in front of you.

Two specific mechanisms require it:

1. **The commercial build imports the server in-process.** Perennia's hosted service is
   the same server as the open-source one, with licensed data providers injected and a
   small number of private routes mounted alongside. That combined program is a derivative
   work of AGPL-licensed code. Without the right to relicense your contribution, third-party
   copyright inside the server would force publication of those private routes.
2. **The official app ships through the App Store.** Apple's distribution terms conflict
   with the GPL family's restrictions. Publishing an AGPL app carrying third-party
   copyright through the App Store requires the right to relicense — the problem that
   removed VLC from the store.

### The asymmetry, stated plainly

This is the part we commit to in public, and you should hold us to it:

> **The commercial edge is a managed service, never a capability wall.** What is sold is
> what costs money to operate — hosting, licensed reference databases, managed
> integrations, inference, support. Contributed code ships identically to self-hosters and
> to paying customers. Features are never withheld from the open-source product to create
> upgrade pressure, and the agent API and MCP surface are identical everywhere. Your data
> is never held hostage; convenience is what is sold.

If you are not comfortable with that trade, we would genuinely rather you didn't sign. A
fork under AGPL is a legitimate response and we will not pretend otherwise.

## Licensing map

Which licence applies depends on where the file lives:

| Path | Licence | Why |
|---|---|---|
| `apps/mobile`, `apps/server`, `sidecars/` | **AGPL-3.0** | Strong copyleft: a fork must publish source whether it ships an app or hosts a service |
| `packages/contract`, `packages/golden-vectors`, `examples/`, the generated agent-skill command map | **Apache-2.0** | Interface artifacts that third-party agents and clients — including proprietary ones — must be able to consume without copyleft friction |

If you add a new package, work out which side of that line it falls on before you write
much code. Interface and contract artifacts go Apache; anything that is the product itself
goes AGPL.

## Before you open a pull request

**Run the gate locally.** CI mirrors it job-for-job:

```bash
pnpm ci:local --changed
```

Use `pnpm ci:local` for a wide change, `pnpm ci:local --list` to see the jobs. Database
jobs need Docker running — they start an ephemeral Postgres and clean it up.

Enable the pre-push hook so a red push is blocked before it leaves your machine:

```bash
git config core.hooksPath tools/git-hooks
```

## Conventions

**Use the project's vocabulary.** [CONTEXT.md](CONTEXT.md) is the source of truth for
domain terms, and code identifiers, UI copy, and API fields all use them — `Workout` not
`Session`, `archive` not `delete`. If a concept you need isn't there, propose a name in an
issue before inventing one.

**Don't hardcode styling.** [DESIGN.md](DESIGN.md) holds the design tokens. Map them into
the Flutter theme and consume them from there rather than writing colours, radii, or
spacing into widgets.

**Some rules are invariants, not preferences.** A change that violates one is a bug even if
the feature works:

- A Workout is a session, not a day-bucket.
- Sets are self-describing — values and units are stored as entered. Exercise Type is an
  input template, never a schema constraint, and changing it never rewrites history.
- Derived analytics (PRs, e1RM, volume, stats) are computed, never stored or synced.
- User-facing delete means archive. History survives; nothing cascades.
- Restore and import are merge-only. There is no destructive restore path.
- Local writes never block on the network. A set save confirms within one frame.
- Sync is silent last-write-wins with recoverable losers via the Activity Log — no
  conflict dialogs.
- Validation is one shared two-tier module (hard-reject impossible, soft-warn improbable),
  identical for the UI and the agent API, and golden-vectored in both languages.
- The client contains no analytics or tracking, in any mode.

**Tests.** Analytics changes need golden vectors that Dart and TypeScript both satisfy.
Repository changes are tested against real in-memory SQLite. Screen work carries
accessibility tests — contrast in both themes, tap-target size, labelled controls.

**A note on FitNotes.** The navigation and logging ergonomics are deliberately modelled on
FitNotes, which is the reference for *how users move through the app* — not a feature-parity
contract. Never copy their assets: no screenshots, icons, or image files, and no references
to their asset filenames. Link their public help pages by URL if you need to point at
something.

## Reporting security issues

Please don't open a public issue for a security problem. See [SECURITY.md](SECURITY.md) for
how to report privately.
