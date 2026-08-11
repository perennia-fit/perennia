import { applyMigrations } from "./migrations.js";

const databaseUrl = process.env.DATABASE_URL;

if (databaseUrl === undefined || databaseUrl.length === 0) {
  throw new Error("DATABASE_URL is required to run server migrations.");
}

await applyMigrations(databaseUrl);
