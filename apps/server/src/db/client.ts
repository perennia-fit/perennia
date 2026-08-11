import { drizzle, type PostgresJsDatabase } from "drizzle-orm/postgres-js";
import postgres, { type Sql } from "postgres";

import * as schema from "./schema.js";

export type ServerDatabase = PostgresJsDatabase<typeof schema>;

export type DatabaseClient = {
  db: ServerDatabase;
  sql: Sql;
  close(): Promise<void>;
};

export function createDatabaseClient(databaseUrl: string): DatabaseClient {
  const sql = postgres(databaseUrl, {
    max: 5,
    onnotice: () => {}
  });
  const db = drizzle(sql, { schema });

  return {
    db,
    sql,
    async close() {
      await sql.end({ timeout: 5 });
    }
  };
}
