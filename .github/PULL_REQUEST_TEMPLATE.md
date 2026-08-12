<!--
First pull request? CLA Assistant will comment with a link to sign. It is one
click and you only do it once. CONTRIBUTING.md explains why the grant is broader
than the project's own licence — worth reading before you sign.
-->

## What this changes

<!-- The behaviour that differs afterwards. Link an issue if there is one. -->

## Why

<!-- The problem being solved. If a reviewer would ask "why not the simpler
     thing?", answer it here. -->

## How it was verified

<!-- What you ran, and what you observed. `pnpm ci:local --changed` is the gate;
     say if anything could not be checked locally. -->

## Checklist

- [ ] `pnpm ci:local --changed` passes
- [ ] Terminology matches CONTEXT.md (the same words in code, UI, and API)
- [ ] If the API changed, generated clients are regenerated and committed
- [ ] If a rule changed, golden vectors cover it in both languages
- [ ] No derived value became stored, and no local write now waits on the network
