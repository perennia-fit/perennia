import { migrate } from "drizzle-orm/postgres-js/migrator";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { createDatabaseClient } from "./client.js";

const currentDir = dirname(fileURLToPath(import.meta.url));
const defaultMigrationsFolder = resolve(currentDir, "../../drizzle");

export async function applyMigrations(
  databaseUrl: string,
  migrationsFolder = defaultMigrationsFolder
) {
  const database = createDatabaseClient(databaseUrl);

  try {
    await migrate(database.db, { migrationsFolder });
  } finally {
    await database.close();
  }
}
