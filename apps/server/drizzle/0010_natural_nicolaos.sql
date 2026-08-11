CREATE TABLE "external_activities" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"device_id" text NOT NULL,
	"source" text NOT NULL,
	"external_id" text NOT NULL,
	"started_at" timestamp with time zone NOT NULL,
	"ended_at" timestamp with time zone NOT NULL,
	"timezone" text NOT NULL,
	"activity_type" text NOT NULL,
	"summary_json" jsonb NOT NULL,
	"summary_metrics_json" jsonb NOT NULL,
	"sets_json" jsonb,
	"updated_at" timestamp with time zone NOT NULL,
	"deleted_at" timestamp with time zone,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "external_activities" ADD CONSTRAINT "external_activities_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "external_activities_user_source_external_id_unique" ON "external_activities" USING btree ("user_id","source","external_id");--> statement-breakpoint
CREATE INDEX "external_activities_user_updated_at_index" ON "external_activities" USING btree ("user_id","updated_at");
