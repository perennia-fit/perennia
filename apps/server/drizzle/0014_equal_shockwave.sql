CREATE TABLE "activity_links" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"device_id" text NOT NULL,
	"workout_id" text NOT NULL,
	"external_activity_id" text NOT NULL,
	"link_kind" text NOT NULL,
	"updated_at" timestamp with time zone NOT NULL,
	"deleted_at" timestamp with time zone,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "activity_links" ADD CONSTRAINT "activity_links_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activity_links" ADD CONSTRAINT "activity_links_external_activity_id_external_activities_id_fk" FOREIGN KEY ("external_activity_id") REFERENCES "public"."external_activities"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "activity_links_user_workout_id_index" ON "activity_links" USING btree ("user_id","workout_id");--> statement-breakpoint
CREATE UNIQUE INDEX "activity_links_user_external_activity_unique" ON "activity_links" USING btree ("user_id","external_activity_id");