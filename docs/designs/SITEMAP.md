# Design specs

The index of design specs for Perennia. Each spec is the contract a feature was
built against and the record of why it works the way it does. How specs are
written, reviewed, and kept in sync with the code is described in
[AGENTS.md](../../AGENTS.md#development-methodology--spec-driven).

Add a row in the same pull request that adds a spec. Keep rows in date order,
newest last. A superseded spec keeps its row, with its status updated and a link
to what replaced it.

| Spec | Date | Author | Status | Components | Description |
| :--- | :--- | :----- | :----- | :--------- | :---------- |
| [Protocol Schedules and Reminders](protocol-schedules-and-reminders.md) | 2026-10-25 | Leonardo Pinheiro | Approved | Protocols domain (`apps/mobile/lib/domain/protocols`, `apps/mobile/lib/features/protocols`), agent Protocols surface (`apps/server/src/agent-protocols.ts`), `packages/golden-vectors` | Clock-time Schedules with versions, Protocol periods (ongoing, until, on/off cycle, pauses), grouped lock-safe local reminders, a planned-vs-logged day list, and a never-scored consistency view, computed by one Dart/TypeScript core pinned by golden vectors. |
