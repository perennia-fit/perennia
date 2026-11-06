-- Re-key `exercises` from `id` to `(user_id, id)`, like `meal_types`. A retired
-- Platform id is fixed and shared by every install, so an exercise kept for its
-- history exists under the same id in many accounts. With `id` alone the first
-- account to push a kept id owned that row and every other account's push or
-- edit of it was silently dropped. Existing ids are already unique, so every row
-- survives the swap; no table has a foreign key to `exercises`. The old key is
-- the Postgres default name from its column-level PRIMARY KEY.
ALTER TABLE "exercises" DROP CONSTRAINT "exercises_pkey";--> statement-breakpoint
ALTER TABLE "exercises" ADD CONSTRAINT "exercises_user_id_id_pk" PRIMARY KEY("user_id","id");
