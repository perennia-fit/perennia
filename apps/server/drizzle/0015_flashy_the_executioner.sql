CREATE TABLE "integration_statuses" (
	"id" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"credential_id" text NOT NULL,
	"credential_name" text,
	"source" text NOT NULL,
	"condition" text NOT NULL,
	"recovery_action" text NOT NULL,
	"last_successful_at" timestamp with time zone,
	"first_failure_at" timestamp with time zone,
	"last_failure_at" timestamp with time zone,
	"failure_kind" text,
	"trigger" text,
	"retry_after_seconds" integer,
	"next_attempt_at" timestamp with time zone,
	"updated_at" timestamp with time zone NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "integration_statuses" ADD CONSTRAINT "integration_statuses_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "integration_statuses_user_source_credential_unique" ON "integration_statuses" USING btree ("user_id","source","credential_id");--> statement-breakpoint
CREATE INDEX "integration_statuses_user_updated_at_index" ON "integration_statuses" USING btree ("user_id","updated_at");