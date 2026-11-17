-- Protocol plans entered before the Schedule and Reminders change are cleared
-- once and re-entered (docs/designs/protocol-schedules-and-reminders.md, D3).
-- Nothing has shipped, so the only rows in the old shape (instant bounds, one
-- frequency per Schedule) are developer data. Compounds and Doses are kept: a
-- Dose keeps its Protocol tag and name snapshot. The device's Drift migration
-- clears the same four tables, and sync protocol 2 refuses older clients.
DELETE FROM "protocol_target_outcomes";--> statement-breakpoint
DELETE FROM "schedules";--> statement-breakpoint
DELETE FROM "protocol_compounds";--> statement-breakpoint
DELETE FROM "protocols";
