-- Re-key the opaque sync tables whose rows are seeded on every device under
-- FIXED ids (Platform exercise categories, default Meal Types, OTC seed
-- Compounds) from `id` to `(user_id, id)`, like `focuses`. With `id` alone the
-- first account to push a seeded id owned that row and every other account's
-- push or edit of it was silently dropped. Existing ids are already unique, so
-- every row survives the swap; nothing references these tables by FK. The old
-- keys are the Postgres default names from their column-level PRIMARY KEY.
ALTER TABLE "compounds" DROP CONSTRAINT "compounds_pkey";--> statement-breakpoint
ALTER TABLE "exercise_categories" DROP CONSTRAINT "exercise_categories_pkey";--> statement-breakpoint
ALTER TABLE "meal_types" DROP CONSTRAINT "meal_types_pkey";--> statement-breakpoint
ALTER TABLE "compounds" ADD CONSTRAINT "compounds_user_id_id_pk" PRIMARY KEY("user_id","id");--> statement-breakpoint
ALTER TABLE "exercise_categories" ADD CONSTRAINT "exercise_categories_user_id_id_pk" PRIMARY KEY("user_id","id");--> statement-breakpoint
ALTER TABLE "meal_types" ADD CONSTRAINT "meal_types_user_id_id_pk" PRIMARY KEY("user_id","id");
