import { randomUUID } from "node:crypto";

import type { ServerDatabase } from "../db/client.js";
import * as schema from "../db/schema.js";

export type JobHeartbeatInput = {
  jobName: string;
  marker: string;
  kind: string;
  payload?: Record<string, unknown>;
  ranAt?: Date;
};

export type JobHeartbeatResult = {
  inserted: boolean;
  id: string | null;
};

export type JobHeartbeatStore = {
  recordHeartbeat(input: JobHeartbeatInput): Promise<JobHeartbeatResult>;
};

export function createDrizzleJobHeartbeatStore(
  db: ServerDatabase
): JobHeartbeatStore {
  return {
    async recordHeartbeat(input) {
      const id = randomUUID();
      const rows = await db
        .insert(schema.jobHeartbeats)
        .values({
          id,
          jobName: input.jobName,
          marker: input.marker,
          kind: input.kind,
          payload: input.payload ?? {},
          ranAt: input.ranAt ?? new Date()
        })
        .onConflictDoNothing({
          target: [schema.jobHeartbeats.jobName, schema.jobHeartbeats.marker]
        })
        .returning({ id: schema.jobHeartbeats.id });
      const inserted = rows[0];

      return inserted === undefined
        ? { inserted: false, id: null }
        : { inserted: true, id: inserted.id };
    }
  };
}
