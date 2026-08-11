CREATE TABLE "logged_set_tombstone_gc_markers" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"logged_set_id" text NOT NULL,
	"device_id" text NOT NULL,
	"tombstone_updated_at" timestamp with time zone NOT NULL,
	"deleted_at" timestamp with time zone NOT NULL,
	"gc_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "logged_set_tombstone_gc_markers" ADD CONSTRAINT "logged_set_tombstone_gc_markers_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "logged_set_tombstone_gc_markers_user_logged_set_unique" ON "logged_set_tombstone_gc_markers" USING btree ("user_id","logged_set_id");--> statement-breakpoint
CREATE INDEX "logged_set_tombstone_gc_markers_user_id_index" ON "logged_set_tombstone_gc_markers" USING btree ("user_id");