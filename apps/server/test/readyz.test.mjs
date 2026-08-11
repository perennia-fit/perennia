import assert from "node:assert/strict";
import test from "node:test";

import { createMigratedServerApp } from "../src/index.ts";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl && process.env.CI === "true") {
  throw new Error("DATABASE_URL must be set for server Postgres integration tests.");
}

test(
  "Drizzle migrations create the account schema and /readyz probes Postgres",
  { skip: databaseUrl ? false : "DATABASE_URL is not set." },
  async () => {
    const serverApp = await createMigratedServerApp({
      databaseUrl,
      logger: { info() {}, error() {} }
    });

    try {
      const tableRows = await serverApp.database.sql`
        select table_name
        from information_schema.tables
        where table_schema = 'public'
        order by table_name
      `;
      const tableNames = tableRows.map((row) => row.table_name);

      assert.deepEqual(
        tableNames.filter((name) =>
          [
            "account",
            "external_activities",
            "logged_sets",
            "metric_readings",
            "metrics",
            "session",
            "user",
            "verification"
          ].includes(name)
        ),
        [
          "account",
          "external_activities",
          "logged_sets",
          "metric_readings",
          "metrics",
          "session",
          "user",
          "verification"
        ]
      );

      const response = await serverApp.app.request("/readyz");

      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), {
        status: "ready",
        database: "ok"
      });
    } finally {
      await serverApp.database.close();
    }
  }
);
