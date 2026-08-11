CREATE TABLE "monitoring_series" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"device_id" text NOT NULL,
	"external_activity_id" text,
	"source" text NOT NULL,
	"external_id" text NOT NULL,
	"series_type" text NOT NULL,
	"anchor_json" jsonb NOT NULL,
	"base_time" timestamp with time zone NOT NULL,
	"timezone" text NOT NULL,
	"sample_count" integer NOT NULL,
	"encoding" text NOT NULL,
	"compression" text NOT NULL,
	"blob" "bytea" NOT NULL,
	"uncompressed_byte_length" integer NOT NULL,
	"compressed_byte_length" integer NOT NULL,
	"sha256" text NOT NULL,
	"provenance" text NOT NULL,
	"updated_at" timestamp with time zone NOT NULL,
	"deleted_at" timestamp with time zone,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "monitoring_series" ADD CONSTRAINT "monitoring_series_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "monitoring_series" ADD CONSTRAINT "monitoring_series_external_activity_id_external_activities_id_fk" FOREIGN KEY ("external_activity_id") REFERENCES "public"."external_activities"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "monitoring_series_user_source_external_id_unique" ON "monitoring_series" USING btree ("user_id","source","external_id");--> statement-breakpoint
CREATE INDEX "monitoring_series_external_activity_id_index" ON "monitoring_series" USING btree ("external_activity_id");--> statement-breakpoint
CREATE INDEX "monitoring_series_user_updated_at_index" ON "monitoring_series" USING btree ("user_id","updated_at");