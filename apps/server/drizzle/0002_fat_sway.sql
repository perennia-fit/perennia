CREATE TABLE "job_heartbeats" (
	"id" text PRIMARY KEY NOT NULL,
	"job_name" text NOT NULL,
	"marker" text NOT NULL,
	"kind" text NOT NULL,
	"payload" jsonb NOT NULL,
	"ran_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX "job_heartbeats_job_marker_unique" ON "job_heartbeats" USING btree ("job_name","marker");--> statement-breakpoint
CREATE INDEX "job_heartbeats_job_ran_at_index" ON "job_heartbeats" USING btree ("job_name","ran_at");