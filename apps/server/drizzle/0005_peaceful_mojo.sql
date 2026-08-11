CREATE TABLE "activity_log" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"actor" text NOT NULL,
	"batch_id" text NOT NULL,
	"entity_table" text NOT NULL,
	"entity_id" text NOT NULL,
	"before_image" jsonb,
	"after_image" jsonb,
	"occurred_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "activity_log" ADD CONSTRAINT "activity_log_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "activity_log_batch_id_index" ON "activity_log" USING btree ("batch_id");--> statement-breakpoint
CREATE INDEX "activity_log_occurred_at_index" ON "activity_log" USING btree ("occurred_at");--> statement-breakpoint
CREATE INDEX "activity_log_user_occurred_at_index" ON "activity_log" USING btree ("user_id","occurred_at");