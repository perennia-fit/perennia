@AGENTS.md

## Claude Code specifics

Everything in AGENTS.md applies. These notes cover only what is different in
Claude Code.

### The EGM plugin

The spec-driven loop in AGENTS.md runs on the Elephant-Goldfish Model plugin.
`.claude/` is gitignored, so each developer installs it once, at user scope:

```bash
claude plugin marketplace add google/elephant-goldfish-model && claude plugin install egm@egm
```

It needs Claude Code 2.1.271 or later, which is what keeps project instructions
out of the Goldfish reviewers' context.

- Commands carry the plugin prefix: `/egm:egm-brainstorm`, `/egm:egm-draft`,
  `/egm:egm-review`, `/egm:egm-resolve`, `/egm:egm-drift-report`.
- The EGM skills are user-invoked only; the `Skill` tool refuses them. When one
  skill hands off to another (review → resolve, for example), read that skill's
  `SKILL.md` and follow it in the same thread.
- Briefs, drafts, and reports go to the `EGM artifact directory` named in
  AGENTS.md, not the session scratchpad: they have to outlive the session.

### Goldfish reviewers see none of this

Reviewers are spawned with `omitClaudeMd: true` and no conversation history.
They do not see this file, AGENTS.md, or anything decided in chat. Two
consequences:

- When `/egm:egm-review` asks for Goldfish context, pass `AGENTS.md`,
  `CONTEXT.md`, and `ARCHITECTURE.md` (and `DESIGN.md` for UI work), unless the
  spec already links them.
- Never answer a reviewer's finding with "we agreed on that earlier". If the
  reasoning isn't in the spec, the finding is correct: put it in the spec.
