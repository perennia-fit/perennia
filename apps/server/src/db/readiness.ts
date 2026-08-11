import { sql } from "drizzle-orm";

import type { ServerDatabase } from "./client.js";

export type ReadinessProbe = {
  check(): Promise<void>;
};

export function createDrizzleReadinessProbe(
  db: ServerDatabase
): ReadinessProbe {
  return {
    async check() {
      await db.execute(sql`select 1`);
    }
  };
}
