import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("Metric migration backfills legacy Measurement rows without destructive writes", async () => {
  const migrationSql = await readFile(
    new URL("../drizzle/0009_cynical_bushwacker.sql", import.meta.url),
    "utf8"
  );

  assert.match(migrationSql, /CREATE TABLE "metrics"/);
  assert.match(migrationSql, /CREATE TABLE "metric_readings"/);
  assert.match(migrationSql, /"comment" text/);
  assert.match(migrationSql, /Defensive legacy-data bridge/);
  assert.match(migrationSql, /out-of-band Measurement deployments/);
  assert.match(migrationSql, /to_regclass\('public\.measurements'\)/);
  assert.match(migrationSql, /to_regclass\('public\.measurement_entries'\)/);
  assert.match(migrationSql, /INSERT INTO "metrics"/);
  assert.match(migrationSql, /INSERT INTO "metric_readings"/);
  assert.match(migrationSql, /'bodyComposition'/);
  assert.match(migrationSql, /'manual'/);
  assert.match(migrationSql, /jsonb_build_object/);
  assert.equal(
    migrationSql.match(/ON CONFLICT \("id"\) DO NOTHING/g)?.length,
    2
  );
  assert.doesNotMatch(
    migrationSql,
    /(?:DROP TABLE|DELETE FROM|TRUNCATE)\s+"?measurements"?/i
  );
  assert.doesNotMatch(
    migrationSql,
    /(?:DROP TABLE|DELETE FROM|TRUNCATE)\s+"?measurement_entries"?/i
  );
});

test("Metric Reading activity-link migration keeps existing readings intact", async () => {
  const migrationSql = await readFile(
    new URL("../drizzle/0011_fantastic_spitfire.sql", import.meta.url),
    "utf8"
  );

  assert.match(
    migrationSql,
    /ALTER TABLE "metric_readings" ADD COLUMN "external_activity_id" text/
  );
  assert.match(
    migrationSql,
    /CREATE INDEX "metric_readings_external_activity_id_index" ON "metric_readings" USING btree \("external_activity_id"\)/
  );
  assert.doesNotMatch(
    migrationSql,
    /(?:DROP TABLE|DELETE FROM|TRUNCATE)\s+"?metric_readings"?/i
  );
});
