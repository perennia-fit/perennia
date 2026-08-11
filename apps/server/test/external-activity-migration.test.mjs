import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("External Activity migration creates immutable source-record storage", async () => {
  const migrationSql = await readFile(
    new URL("../drizzle/0010_natural_nicolaos.sql", import.meta.url),
    "utf8"
  );

  assert.match(migrationSql, /CREATE TABLE "external_activities"/);
  assert.match(migrationSql, /"id" text PRIMARY KEY NOT NULL/);
  assert.match(migrationSql, /"source" text NOT NULL/);
  assert.match(migrationSql, /"external_id" text NOT NULL/);
  assert.match(migrationSql, /"activity_type" text NOT NULL/);
  assert.match(migrationSql, /"summary_json" jsonb NOT NULL/);
  assert.match(migrationSql, /"summary_metrics_json" jsonb NOT NULL/);
  assert.match(migrationSql, /"sets_json" jsonb/);
  assert.match(migrationSql, /"updated_at" timestamp with time zone NOT NULL/);
  assert.match(migrationSql, /"deleted_at" timestamp with time zone/);
  assert.match(
    migrationSql,
    /CREATE UNIQUE INDEX "external_activities_user_source_external_id_unique" ON "external_activities" USING btree \("user_id","source","external_id"\)/
  );
});

test("Activity Link migration creates source-to-workout join storage", async () => {
  const migrationSql = await readFile(
    new URL("../drizzle/0014_equal_shockwave.sql", import.meta.url),
    "utf8"
  );

  assert.match(migrationSql, /CREATE TABLE "activity_links"/);
  assert.match(migrationSql, /"workout_id" text NOT NULL/);
  assert.match(migrationSql, /"external_activity_id" text NOT NULL/);
  assert.match(migrationSql, /"link_kind" text NOT NULL/);
  assert.match(migrationSql, /"deleted_at" timestamp with time zone/);
  assert.match(
    migrationSql,
    /FOREIGN KEY \("external_activity_id"\) REFERENCES "public"."external_activities"\("id"\)/
  );
  assert.match(
    migrationSql,
    /CREATE INDEX "activity_links_user_workout_id_index" ON "activity_links" USING btree \("user_id","workout_id"\)/
  );
  assert.match(
    migrationSql,
    /CREATE UNIQUE INDEX "activity_links_user_external_activity_unique" ON "activity_links" USING btree \("user_id","external_activity_id"\)/
  );
});
