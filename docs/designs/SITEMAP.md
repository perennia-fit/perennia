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
| [Protocol Schedules and Reminders](protocol-schedules-and-reminders.md) | 2026-10-25 | Leonardo Pinheiro | Current | Protocols domain (`apps/mobile/lib/domain/protocols`, `apps/mobile/lib/features/protocols`), agent Protocols surface (`apps/server/src/agent-protocols.ts`), `packages/golden-vectors` | Clock-time Schedules with versions, Protocol periods (ongoing, until, on/off cycle, pauses), grouped lock-safe local reminders, a planned-vs-logged day list, and a never-scored consistency view, computed by one Dart/TypeScript core pinned by golden vectors. |
| [Open Food Facts Integration](open-food-facts.md) | 2026-10-25 | Leonardo Pinheiro | Current | Nutrition domain (`apps/mobile/lib/domain/nutrition/open_food_facts.dart`, `apps/mobile/lib/features/nutrition`, `apps/mobile/lib/data/local/food_reference_database.dart`), the bundle and its builder (`apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz`, `apps/mobile/tool/open_food_facts_bundle/build_bundle.dart`), agent food search (`apps/server/src/agent-foods.ts`, `apps/server/src/open-food-facts-bundle.ts`, `apps/server/src/barcode-candidates.ts`), `packages/golden-vectors` | An offline ODbL bundle of common products from five launch countries, live search and barcode lookup within Open Food Facts' rules, per-food attribution and accuracy disclaimer, and agent parity through `search-platform-foods`. |
| [Protocol Target Outcome Sync Shape](protocol-target-outcome-sync-shape.md) | 2026-10-28 | Leonardo Pinheiro | In Review | Agent Protocols write and read (`apps/server/src/agent-protocols.ts`), the app's target-outcome sync decoder (`apps/mobile/lib/data/repositories/training_repositories.dart`), the contract | Makes an Agent-written Protocol target outcome store the payload the app stores (`kind` and `position`), so it syncs to the app instead of stalling every pull; reads rows stored in the old `outcome_kind` shape on both sides. |
